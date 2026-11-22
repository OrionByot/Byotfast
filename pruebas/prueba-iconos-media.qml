import QtQuick
import QtQuick.Window
import "../cerrar-ventanas/widgets" as Widgets
Window {
    visible: true
    width: 300
    height: 120
    Row {
        spacing: 4
        Repeater {
            model: ["Anterior", "Reproducir", "Siguiente"]
            Widgets.IconoMedia {
                required property string modelData
                accion: modelData
                tinta: "#ffffff"
                width: 64
                height: width
            }
        }
    }
    Timer { interval: 100; running: true; onTriggered: Qt.quit() }
}
