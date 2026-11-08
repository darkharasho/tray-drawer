# Tray Drawer

A Plasma 6 panel widget that slides the System Tray's **Always hidden** icons into the
panel and back, like a macOS menu bar drawer.

Closed:

![Tray Drawer closed](docs/closed.png)

Open:

![Tray Drawer open](docs/open.png)

It doesn't draw tray icons itself. It moves entries between the tray's `hiddenItems` and
`shownItems` (through plasmashell's `evaluateScript` D-Bus API), one at a time, so the real
tray keeps handling icons, menus and popups, including built-in ones like clipboard and battery.

- Place it just left of the System Tray in the same panel.
- Pick what goes in the drawer with System Tray Settings → Entries → "Always hidden".
- Settings: auto-hide delay (default 15 s, 0 = never), per-icon slide delay (default 45 ms,
  0 = all at once), open on hover, show icons that need attention.
- Every panel with a Tray Drawer shares one Always shown / Always hidden list. Change it in
  any tray's settings and the others follow within about 5 s. The shared state is kept in
  the tray's own config (`trayDrawerSyncHidden`, `trayDrawerSyncShown`, `trayDrawerSynced`).
- A hidden app whose tray icon reports `NeedsAttention` (StatusNotifierItem status, polled
  every 2 s) is shown until the status clears, even when the drawer is closed.
- Icons out of the drawer are tracked in the tray's config (`trayDrawerTemp`) and hidden
  again when the widget starts, in case plasmashell exited while the drawer was open.
- No divider between shown and revealed icons: the System Tray sorts its icons by category
  and name, so revealed icons mix in with the always-shown ones.

Install / update:

    kpackagetool6 -t Plasma/Applet -i package   # first time
    kpackagetool6 -t Plasma/Applet -u package   # updates (restart plasmashell to load new QML)
