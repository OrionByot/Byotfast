import QtQuick
import QtQuick.Window
import "../cerrar-ventanas/widgets" as Widgets
Window {
    visible: true
    width: 360
    height: 280
    Widgets.MarcoFoto {
        width: 300
        height: 190
        preferencias: ({})
        tinta: "white"
        editable: true
    }
    Widgets.BusquedaGoogle {
        y: 190
        width: 300
        height: 60
        tinta: "white"
        acento: "teal"
        fondo: "#20252c"
    }
    Timer { interval: 350; running: true; onTriggered: Qt.quit() }
}
