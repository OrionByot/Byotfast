pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.ToolButton {
    id: boton
    required property color acento
    required property bool restaurar
    property bool mostrarSimbolo: true
    property string simbolo: "window-minimize"
    readonly property bool resaltado: hovered || visualFocus || down
    implicitWidth: 28
    implicitHeight: 28
    hoverEnabled: true
    text: restaurar ? "Restaurar widget" : "Minimizar widget"
    Accessible.name: text
    Controls.ToolTip.visible: hovered
    Controls.ToolTip.text: text
    background: Item {}
    contentItem: Item {
        Rectangle {
            id: circulo
            anchors.centerIn: parent
            width: boton.resaltado ? 20 : 9
            height: width
            radius: width / 2
            color: boton.acento
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 12
                height: 12
                source: boton.simbolo
                rotation: boton.restaurar ? 180 : 0
                visible: boton.mostrarSimbolo && boton.resaltado
                color: 0.2126 * boton.acento.r + 0.7152 * boton.acento.g + 0.0722 * boton.acento.b > 0.57
                       ? "#102034" : "#ffffff"
                isMask: true
            }
        }
    }
}
