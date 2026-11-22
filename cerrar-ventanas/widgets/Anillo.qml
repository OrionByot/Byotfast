pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Shapes

Item {
    id: anillo
    required property real nivel
    required property color tinta
    required property color acento
    property bool mostrarRayo: false
    readonly property real porcentaje: Math.max(0, Math.min(100, nivel))
    implicitWidth: 66
    implicitHeight: 66

    Shape {
        id: figura
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        readonly property real centroX: width / 2
        readonly property real centroY: height / 2
        readonly property real radio: Math.max(0, Math.min(width, height) / 2 - grosor / 2 - 2)
        readonly property real grosor: Math.min(width, height) / 11

        ShapePath {
            strokeColor: Qt.alpha(anillo.tinta, 0.20)
            strokeWidth: figura.grosor
            fillColor: "transparent"
            PathAngleArc {
                centerX: figura.centroX
                centerY: figura.centroY
                radiusX: figura.radio
                radiusY: figura.radio
                startAngle: -90
                sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: anillo.porcentaje > 0 ? anillo.acento : "transparent"
            strokeWidth: figura.grosor
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: figura.centroX
                centerY: figura.centroY
                radiusX: figura.radio
                radiusY: figura.radio
                startAngle: -90
                sweepAngle: 3.6 * anillo.porcentaje
            }
        }
    }

    Controls.Label {
        anchors.centerIn: parent
        text: anillo.nivel < 0 ? "…" : Math.round(anillo.porcentaje) + "%" + (anillo.mostrarRayo ? " ⚡︎" : "")
        color: anillo.tinta
        font.bold: true
    }
}
