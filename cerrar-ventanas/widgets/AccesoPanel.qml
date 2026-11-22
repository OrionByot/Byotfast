pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.AbstractButton {
    id: acceso
    required property color acento
    required property string titulo
    property bool vertical: false
    property bool desplegable: false
    property bool abierto: false
    property bool mostrarAyuda: true
    property bool resaltarAbierto: true
    property int anchoTexto: 114
    property string textoVertical: ""
    readonly property bool apilado: vertical && !!textoVertical
    implicitWidth: indicadores.implicitWidth + 10
    implicitHeight: indicadores.implicitHeight + 6
    Layout.minimumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Accessible.name: titulo + (text ? " · " + text : "")
    hoverEnabled: true
    Controls.ToolTip.visible: mostrarAyuda && hovered && !abierto
    Controls.ToolTip.delay: 550
    Controls.ToolTip.text: titulo + (text ? " · " + text : "")
    background: Rectangle {
        radius: 6
        color: acceso.down || acceso.visualFocus || (acceso.resaltarAbierto && acceso.abierto) ? Qt.alpha(acceso.acento, 0.18) : "transparent"
    }
    contentItem: Item {
        GridLayout {
            id: indicadores
            anchors.centerIn: parent
            columns: acceso.apilado ? 1 : 3
            rowSpacing: 0
            columnSpacing: 5
            Kirigami.Icon {
                visible: !acceso.apilado
                source: acceso.icon.name
                color: acceso.acento
                isMask: true
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
            }
            Controls.Label {
                visible: acceso.apilado || (!acceso.vertical && !!acceso.text)
                text: acceso.apilado ? acceso.textoVertical : acceso.text
                horizontalAlignment: Text.AlignHCenter
                Binding on font.pixelSize {
                    when: acceso.apilado
                    value: 10
                }
                textFormat: Text.PlainText
                elide: Text.ElideRight
                Layout.maximumWidth: acceso.anchoTexto
            }
            Kirigami.Icon {
                visible: acceso.desplegable && !acceso.vertical
                source: "go-down"
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
            }
        }
    }
}
