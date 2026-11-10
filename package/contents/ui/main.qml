/*
    Tray Drawer: slides the System Tray's "Always hidden" icons into the panel and back.

    It doesn't draw any tray icons itself. It edits the shownItems/hiddenItems lists of the
    System Tray in the same panel (through plasmashell's scripting D-Bus API), one icon at a
    time, so the real tray handles icons, menus and popups as usual.
*/


import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // What the user asked for; the pump works the tray toward this state.
    property bool wantOpen: false
    // Icons still waiting to move into the panel during an open.
    property var toReveal: []
    // Icons the drawer has moved into the panel, in the order they came out.
    property var revealed: []
    // Hidden icons shown because their app asked for attention.
    property var attention: []
    // The synced "Always hidden" list, including icons that are out right now.
    property var allHidden: []
    property bool busy: false
    property bool trayFound: true
    property int hiddenCount: 0
    // Whether this drawer runs the periodic sync (only one drawer across all panels does).
    property bool syncLeader: true
    property DBus.DBusPendingReply pendingReply

    // No full representation: the arrow button below is the whole widget.
    readonly property int iconSize: Kirigami.Units.iconSizes.small
    Layout.minimumWidth: vertical ? -1 : iconSize + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: vertical ? -1 : Layout.minimumWidth
    Layout.minimumHeight: vertical ? iconSize + Kirigami.Units.smallSpacing * 2 : -1
    Layout.preferredHeight: Layout.minimumHeight
    Layout.maximumHeight: vertical ? Layout.minimumHeight : -1
    Plasmoid.icon: vertical ? "arrow-up" : "arrow-left"
    toolTipMainText: wantOpen ? i18n("Hide tray icons") : i18n("Show hidden tray icons")
    toolTipSubText: !trayFound ? i18n("No System Tray found in this panel")
                  : (hiddenCount > 0 ? i18np("%1 hidden icon", "%1 hidden icons", hiddenCount) : "")

    // ---- plasmashell scripting -------------------------------------------------------

    // Every call also syncs the shown/hidden lists of all trays that have a Tray Drawer in
    // their panel. Icons the drawer shows temporarily are tracked in the tray's own config
    // (trayDrawerTemp), so the script, not this widget, is the source of truth.
    function buildScript(mode, items) {
        return "(function () {\n"
            + "var anchorId = " + JSON.stringify(Plasmoid.id) + ", mode = " + JSON.stringify(mode)
            + ", items = " + JSON.stringify(items) + ", drawerType = " + JSON.stringify(Plasmoid.pluginName) + ";\n"
            + `var trays = [], drawers = [];
function list(v) { if (!v) return []; if (typeof v === "string") return v.length ? v.split(",") : []; return Array.prototype.slice.call(v); }
function uniq(a) { return a.filter(function (x, i) { return x && a.indexOf(x) === i; }); }
function minus(a, b) { return a.filter(function (x) { return b.indexOf(x) < 0; }); }
function flat(key) { var r = []; trays.forEach(function (t) { r = r.concat(t[key]); }); return uniq(r); }
function put(t, key, val, old) { if (String(val) !== String(old)) t.w.writeConfig(key, val); }
panels().forEach(function (p) {
  var ws = p.widgets(), tray = null;
  ws.forEach(function (w) { if (w.type === drawerType) drawers.push(Number(w.id)); });
  if (!ws.some(function (w) { return w.type === drawerType; })) return;
  ws.forEach(function (w) { if (!tray && w.type === "org.kde.plasma.systemtray") tray = w; });
  if (!tray) return;
  tray.currentConfigGroup = ["General"];
  var shown = list(tray.readConfig("shownItems")), hidden = list(tray.readConfig("hiddenItems"));
  var temp = list(tray.readConfig("trayDrawerTemp")).filter(function (x) { return shown.indexOf(x) >= 0; });
  var synced = String(tray.readConfig("trayDrawerSynced")) === "true";
  trays.push({ w: tray, own: ws.some(function (w) { return w.id == anchorId; }), temp: temp, oldTemp: temp.slice(),
    shown: shown, hidden: hidden, effHidden: uniq(hidden.concat(temp)), effShown: minus(shown, temp), synced: synced,
    baseH: list(tray.readConfig("trayDrawerSyncHidden")), baseS: list(tray.readConfig("trayDrawerSyncShown")) });
});
var base = null; trays.forEach(function (t) { if (!base && t.synced) base = t; });
var H, S;
if (!base) {
  H = flat("effHidden"); S = minus(flat("effShown"), H);
} else {
  var merge = function (B, key) {
    var add = [], rem = [];
    trays.forEach(function (t) { add = add.concat(minus(t[key], B)); if (t.synced) rem = rem.concat(minus(B, t[key])); });
    return uniq(minus(B, rem).concat(add));
  };
  H = merge(base.baseH, "effHidden"); S = merge(base.baseS, "effShown");
  var newS = minus(S, base.baseS);
  H = H.filter(function (x) { return !(S.indexOf(x) >= 0 && newS.indexOf(x) >= 0); });
  S = minus(S, H);
}
// Only one drawer (the lowest id) needs to do the periodic background sync.
var res = { found: false, hidden: [], temp: [], allHidden: H, leader: Number(anchorId) === Math.min.apply(null, drawers) };
trays.forEach(function (t) {
  if (t.own) {
    res.found = true;
    if (mode === "show") items.forEach(function (id) { if (H.indexOf(id) >= 0 && t.temp.indexOf(id) < 0) t.temp.push(id); });
    if (mode === "hide") t.temp = minus(t.temp, items);
    if (mode === "reset") t.temp = [];
  }
  t.temp = t.temp.filter(function (x) { return H.indexOf(x) >= 0; });
  var hidden = minus(H, t.temp), shown = uniq(S.concat(t.temp));
  // Write only what changed: any write makes plasmashell reload the tray's config.
  put(t, "hiddenItems", hidden, t.hidden);
  put(t, "shownItems", shown, t.shown);
  put(t, "trayDrawerTemp", t.temp, t.oldTemp);
  put(t, "trayDrawerSyncHidden", H, t.baseH);
  put(t, "trayDrawerSyncShown", S, t.baseS);
  if (!t.synced) t.w.writeConfig("trayDrawerSynced", "true");
  if (t.own) { res.hidden = hidden; res.temp = t.temp; }
});
print(JSON.stringify(res));
})();`;
    }

    function runScript(mode, items, onDone) {
        busy = true;
        const reply = DBus.SessionBus.asyncCall({
            "service": "org.kde.plasmashell",
            "path": "/PlasmaShell",
            "iface": "org.kde.PlasmaShell",
            "member": "evaluateScript",
            "arguments": [new DBus.string(buildScript(mode, items))],
            "signature": "(s)"
        });
        pendingReply = reply;
        reply.finished.connect(() => {
            let res = null;
            if (reply.isError) {
                console.warn("Tray Drawer: evaluateScript failed:", reply.error.message);
            } else {
                const lines = String(reply.value).trim().split("\n");
                for (let i = lines.length - 1; i >= 0 && !res; --i) {
                    try { res = JSON.parse(lines[i]); } catch (e) { /* not our line */ }
                }
            }
            busy = false;
            if (res) {
                trayFound = res.found;
                hiddenCount = res.hidden.length;
                allHidden = res.allHidden;
                syncLeader = res.leader !== false;
            }
            onDone(res);
        });
    }

    // ---- state machine ---------------------------------------------------------------

    function setOpen(open) {
        if (open === wantOpen) {
            return;
        }
        wantOpen = open;
        collapseTimer.stop();
        if (open) {
            // Find out what's hidden right now, then reveal it piece by piece.
            toReveal = [];
            whenIdle(() => runScript("query", [], (res) => {
                if (!res || !res.found) {
                    wantOpen = false;
                    return;
                }
                // Reveal the icons nearest the tray's arrow first.
                toReveal = res.hidden.filter(id => revealed.indexOf(id) < 0).reverse();
                pump();
            }));
        } else {
            toReveal = [];
            pump();
        }
    }

    function toggle() {
        setOpen(!wantOpen);
    }

    property var idleQueue: []
    function whenIdle(fn) {
        if (busy) {
            idleQueue.push(fn);
        } else {
            fn();
        }
    }

    // Moves the next icon (or all of them when the delay is 0) and schedules the next step.
    function pump() {
        if (busy) {
            return;
        }
        if (idleQueue.length) {
            idleQueue.shift()();
            return;
        }
        const batch = Plasmoid.configuration.staggerMs <= 0;
        if (wantOpen && toReveal.length) {
            const items = batch ? toReveal.splice(0) : [toReveal.shift()];
            runScript("show", items, (res) => {
                if (res && res.found) {
                    revealed = revealed.concat(items.filter(id => revealed.indexOf(id) < 0));
                }
                stepTimer.restart();
            });
        } else if (!wantOpen && revealed.length) {
            const items = batch ? revealed.slice().reverse() : [revealed[revealed.length - 1]];
            // Icons asking for attention stay out after the drawer closes.
            const toHide = items.filter(id => attention.indexOf(id) < 0);
            runScript(toHide.length ? "hide" : "query", toHide, (res) => {
                if (res) {
                    revealed = revealed.filter(id => items.indexOf(id) < 0);
                }
                stepTimer.restart();
            });
        } else if (wantOpen && Plasmoid.configuration.autoCollapseSeconds > 0) {
            collapseTimer.restart();
        }
    }

    Timer {
        id: stepTimer
        interval: Math.max(1, Plasmoid.configuration.staggerMs)
        onTriggered: root.pump()
    }

    Timer {
        id: collapseTimer
        interval: Plasmoid.configuration.autoCollapseSeconds * 1000
        onTriggered: root.setOpen(false)
    }

    // ---- needs-attention icons -------------------------------------------------------

    function dbusGet(service, path, iface, prop, onDone) {
        const reply = DBus.SessionBus.asyncCall({
            "service": service,
            "path": path,
            "iface": "org.freedesktop.DBus.Properties",
            "member": "Get",
            "arguments": [new DBus.string(iface), new DBus.string(prop)],
            "signature": "(ss)"
        });
        reply.finished.connect(() => onDone(reply.isError ? undefined : reply.value));
        return reply;
    }

    property var sniIds: ({})        // "service/path" -> SNI Id
    property var pendingPolls: []    // keeps the replies alive until they finish
    property bool polling: false

    function pollAttention() {
        if (polling) {
            return;
        }
        polling = true;
        const keep = [];
        keep.push(dbusGet("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                          "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems", (value) => {
            const regs = value ? Array.prototype.slice.call(value) : [];
            let left = regs.length;
            const flagged = [];
            const done = () => {
                if (--left > 0) {
                    return;
                }
                pendingPolls = [];
                polling = false;
                applyAttention(flagged);
            };
            if (!left) {
                left = 1;
                done();
                return;
            }
            regs.forEach((reg) => {
                const key = String(reg);
                const slash = key.indexOf("/");
                const service = slash < 0 ? key : key.slice(0, slash);
                const path = slash < 0 ? "/StatusNotifierItem" : key.slice(slash);
                const withId = (id) => {
                    keep.push(dbusGet(service, path, "org.kde.StatusNotifierItem", "Status", (status) => {
                        if (id && String(status) === "NeedsAttention") {
                            flagged.push(id);
                        }
                        done();
                    }));
                };
                if (sniIds[key] !== undefined) {
                    withId(sniIds[key]);
                } else {
                    keep.push(dbusGet(service, path, "org.kde.StatusNotifierItem", "Id", (id) => {
                        if (id !== undefined) {
                            sniIds[key] = String(id);
                        }
                        withId(id === undefined ? "" : String(id));
                    }));
                }
            });
        }));
        pendingPolls = keep;
    }

    // flagged: SNI Ids currently asking for attention. Hidden entries can be "Id" or "Id@process".
    function applyAttention(flagged) {
        const now = allHidden.filter(entry => flagged.some(id => entry === id || entry.indexOf(id + "@") === 0));
        const started = now.filter(id => attention.indexOf(id) < 0);
        const ended = attention.filter(id => now.indexOf(id) < 0);
        if (!started.length && !ended.length) {
            return;
        }
        attention = now;
        const toShow = started.filter(id => revealed.indexOf(id) < 0);
        const toHide = ended.filter(id => revealed.indexOf(id) < 0);
        if (toShow.length) {
            whenIdle(() => runScript("show", toShow, () => root.pump()));
        }
        if (toHide.length) {
            whenIdle(() => runScript("hide", toHide, () => root.pump()));
        }
    }

    Timer {
        id: attentionTimer
        interval: 2000
        repeat: true
        running: Plasmoid.configuration.showOnAttention
        onTriggered: root.pollAttention()
    }

    Connections {
        target: Plasmoid.configuration
        function onShowOnAttentionChanged() {
            if (!Plasmoid.configuration.showOnAttention) {
                root.applyAttention([]);
            }
        }
    }

    // Picks up changes made in either tray's settings and copies them to the other trays.
    // Every evaluateScript call spins up a script engine inside plasmashell, so keep this
    // rare; opening the drawer also syncs.
    Timer {
        interval: 30000
        repeat: true
        running: root.syncLeader
        onTriggered: {
            if (!root.busy && !root.toReveal.length && !root.idleQueue.length) {
                root.runScript("query", [], () => root.pump());
            }
        }
    }

    Timer {
        id: hoverTimer
        interval: 250
        onTriggered: root.setOpen(true)
    }

    Component.onCompleted: {
        // Put back anything left in the panel by a crash or logout while open.
        runScript("reset", [], () => root.pump());
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            root.toggle();
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.wantOpen ? i18n("Hide Icons") : i18n("Show Hidden Icons")
            icon.name: root.vertical ? "arrow-up" : "arrow-left"
            onTriggered: root.toggle()
        }
    ]

    // ---- panel button ----------------------------------------------------------------

    MouseArea {
        id: button
        anchors.fill: parent

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: {
            hoverTimer.stop();
            root.toggle();
        }
        onContainsMouseChanged: {
            if (containsMouse) {
                if (Plasmoid.configuration.expandOnHover && !root.wantOpen) {
                    hoverTimer.restart();
                }
                if (collapseTimer.running) {
                    collapseTimer.restart();
                }
            } else {
                hoverTimer.stop();
            }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            source: root.vertical ? "arrow-up" : "arrow-left"
            active: button.containsMouse
            opacity: root.trayFound ? 1 : 0.4
            rotation: root.wantOpen ? 180 : 0
            Behavior on rotation {
                RotationAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }
}
