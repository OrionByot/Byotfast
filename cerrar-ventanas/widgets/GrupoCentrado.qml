import QtQuick
import QtQuick.Layouts

Item {
    id: grupo
    default property alias elementos: contenido.data
    property alias spacing: contenido.spacing
    implicitWidth: contenido.implicitWidth
    implicitHeight: contenido.implicitHeight
    Layout.fillWidth: true
    Layout.fillHeight: true

    ColumnLayout {
        id: contenido
        width: grupo.width
        anchors.verticalCenter: parent.verticalCenter
    }
}
