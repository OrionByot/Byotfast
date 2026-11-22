pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

Shape {
    id: icono
    required property string accion
    required property color tinta
    property bool sonando: false
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        fillColor: icono.tinta
        PathSvg {
            path: {
                const u = icono.width / 24
                switch (icono.accion) {
                case "Anterior":
                    return `M ${4*u} ${5*u} h ${3*u} v ${14*u} h ${-3*u} Z M ${20*u} ${5*u} L ${8*u} ${12*u} L ${20*u} ${19*u} Z`
                case "Siguiente":
                    return `M ${17*u} ${5*u} h ${3*u} v ${14*u} h ${-3*u} Z M ${4*u} ${5*u} L ${16*u} ${12*u} L ${4*u} ${19*u} Z`
                default:
                    return icono.sonando
                        ? `M ${6*u} ${5*u} h ${4*u} v ${14*u} h ${-4*u} Z M ${14*u} ${5*u} h ${4*u} v ${14*u} h ${-4*u} Z`
                        : `M ${7*u} ${4*u} L ${21*u} ${12*u} L ${7*u} ${20*u} Z`
                }
            }
        }
    }
}
