pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

Shape {
    id: flecha
    required property color colorTrazo
    implicitWidth: 16
    implicitHeight: 16
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: flecha.colorTrazo
        strokeWidth: 1.4
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        startX: flecha.width * 0.34
        startY: flecha.height * 0.16
        PathLine { x: flecha.width * 0.70; y: flecha.height * 0.50 }
        PathLine { x: flecha.width * 0.34; y: flecha.height * 0.84 }
    }
}
