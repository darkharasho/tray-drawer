import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_autoCollapseSeconds: collapseSpin.value
    property alias cfg_staggerMs: staggerSpin.value
    property alias cfg_expandOnHover: hoverCheck.checked
    property alias cfg_showOnAttention: attentionCheck.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: collapseSpin
            Kirigami.FormData.label: i18n("Hide icons again after:")
            from: 0; to: 600
            textFromValue: (v) => v === 0 ? i18n("Never") : i18np("%1 second", "%1 seconds", v)
            valueFromText: (t) => parseInt(t) || 0
        }
        QQC2.SpinBox {
            id: staggerSpin
            Kirigami.FormData.label: i18n("Slide delay per icon:")
            from: 0; to: 300; stepSize: 5
            textFromValue: (v) => v === 0 ? i18n("Instant") : i18n("%1 ms", v)
            valueFromText: (t) => parseInt(t) || 0
        }
        QQC2.CheckBox {
            id: hoverCheck
            Kirigami.FormData.label: i18n("Open:")
            text: i18n("When hovering the arrow")
        }

        QQC2.CheckBox {
            id: attentionCheck
            Kirigami.FormData.label: i18n("Attention:")
            text: i18n("Show a hidden icon while its app needs attention")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Tray Drawer shows the icons set to \"Always hidden\" in this panel's System Tray settings. Place it just left of the System Tray.")
        }
    }
}
