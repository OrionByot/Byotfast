import QtQuick
import QtQuick.Controls as Controls
Window {
    width: 1000
    height: 700
    visible: true
    Item {
        id: marco
        x: 610; y: 100; width: 230; height: 500
        Controls.Dialog {
            id: dialogo
            parent: marco
            popupType: Controls.Popup.Item
            anchors.centerIn: parent
            width: 300
            height: 160
            modal: true
            margins: 8
            Component.onCompleted: open()
        }
    }
    Timer {
        interval: 250
        running: true
        onTriggered: {
            const centro = dialogo.contentItem.mapToItem(marco, 0, 0)
            if (Math.abs(dialogo.x + dialogo.width / 2 - marco.width / 2) > 1 ||
                    Math.abs(dialogo.y + dialogo.height / 2 - marco.height / 2) > 1 || centro.x > marco.width) {
                console.error("La confirmación no quedó centrada.")
                Qt.exit(1)
            } else {
                Qt.quit()
            }
        }
    }
}
