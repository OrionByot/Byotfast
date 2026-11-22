pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.private.containmentlayoutmanager as DesktopLayout

DragHandler {
            id: mover
            required property DesktopLayout.ItemContainer soporte
            required property Item tarjeta
            property Item encabezado: tarjeta
            property Item superficieCursor: tarjeta
            property bool permiteRedimensionar: true
            property bool bloquearInicio: false
            property int ladoHorizontal: 0
            property int ladoVertical: 0
            readonly property bool redimensionando: ladoHorizontal !== 0 || ladoVertical !== 0
            property size tamanoInicial
            readonly property int margen: 8
            readonly property int esquina: 15
            signal tamanoElegido(int ancho, int alto)
            enabled: !!soporte?.layout && (active || !bloquearInicio)
            acceptedButtons: Qt.LeftButton
            acceptedModifiers: Qt.ControlModifier
            dragThreshold: 3
            cursorShape: cursorPara(ladoHorizontal, ladoVertical)
            property HoverHandler avisoCursor: HoverHandler {
                id: aviso
                parent: mover.superficieCursor
                enabled: mover.enabled && !mover.active
                acceptedModifiers: Qt.ControlModifier
                cursorShape: {
                    const posicion = mover.tarjeta.mapFromItem(mover.superficieCursor, point.position)
                    const lados = mover.ladosEn(posicion)
                    if (lados.x || lados.y)
                        return mover.cursorPara(lados.x, lados.y)
                    const encabezado = mover.encabezado
                    const local = encabezado.mapFromItem(mover.tarjeta, posicion)
                    return encabezado.contains(local) ? Qt.SizeAllCursor : Qt.ArrowCursor
                }
            }

            function cursorPara(horizontal: int, vertical: int): int {
                if (horizontal && vertical)
                    return horizontal === vertical ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                return horizontal ? Qt.SizeHorCursor : vertical ? Qt.SizeVerCursor : Qt.SizeAllCursor
            }

            function ladosEn(punto: point): point {
                if (!permiteRedimensionar)
                    return Qt.point(0, 0)
                const x = punto.x
                const y = punto.y
                const cercaHorizontal = x <= esquina || x >= tarjeta.width - esquina
                const cercaVertical = y <= esquina || y >= tarjeta.height - esquina
                const zona = cercaHorizontal && cercaVertical ? esquina : margen
                return Qt.point(x <= zona ? -1 : x >= tarjeta.width - zona ? 1 : 0,
                    y <= zona ? -1 : y >= tarjeta.height - zona ? 1 : 0)
            }

            target: null
            property DesktopLayout.ItemContainer contenedor: null
            property point inicio: Qt.point(0, 0)
            property point inicioCursor: Qt.point(0, 0)
            property bool aplicandoTamano: false
            property point destino: Qt.point(0, 0)
            property real zAnterior: 0
            onActiveChanged: {
                if (active) {
                    contenedor = soporte
                    inicio = Qt.point(contenedor.x, contenedor.y)
                    destino = inicio
                    const presion = centroid.scenePressPosition
                    inicioCursor = contenedor.layout.mapFromItem(null, presion.x, presion.y)
                    const lados = ladosEn(tarjeta.mapFromItem(null, presion.x, presion.y))
                    ladoHorizontal = lados.x
                    ladoVertical = lados.y
                    if (redimensionando) {
                        tamanoInicial = Qt.size(contenedor.width, contenedor.height)
                        if (contenedor.layout.itemIsManaged(contenedor))
                            contenedor.layout.releaseSpace(contenedor)
                    }
                    zAnterior = contenedor.z
                    contenedor.z = 1000
                } else if (contenedor) {
                    if (redimensionando) {
                        contenedor.x = destino.x
                        contenedor.y = destino.y
                        tamanoElegido(Math.round(contenedor.width), Math.round(contenedor.height))
                        contenedor.layout.positionItem(contenedor)
                        contenedor.layout.save()
                        contenedor.z = zAnterior
                        contenedor = null
                        ladoHorizontal = 0
                        ladoVertical = 0
                    } else {
                        contenedor.layout.releaseSpace(contenedor)
                        colocar.start()
                    }
                }
            }
            onActiveTranslationChanged: {
                if (!active || !contenedor || aplicandoTamano)
                    return
                const layout = contenedor.layout
                const actual = layout.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y)
                if (redimensionando) {
                    const dx = actual.x - inicioCursor.x
                    const dy = actual.y - inicioCursor.y
                    aplicandoTamano = true
                    try {
                        let x = inicio.x
                        let y = inicio.y
                        if (ladoHorizontal) {
                            const derecha = inicio.x + tamanoInicial.width
                            const maximo = ladoHorizontal < 0 ? derecha : layout.width - inicio.x
                            const ancho = Math.max(tarjeta.Layout.minimumWidth,
                                Math.min(maximo, tamanoInicial.width + ladoHorizontal * dx))
                            if (ladoHorizontal < 0)
                                x = derecha - ancho
                            contenedor.width = ancho
                        }
                        if (ladoVertical) {
                            const abajo = inicio.y + tamanoInicial.height
                            const maximo = ladoVertical < 0 ? abajo : layout.height - inicio.y
                            const alto = Math.max(tarjeta.Layout.minimumHeight,
                                Math.min(maximo, tamanoInicial.height + ladoVertical * dy))
                            if (ladoVertical < 0)
                                y = abajo - alto
                            contenedor.height = alto
                        }
                        destino = Qt.point(x, y)
                    } finally {
                        aplicandoTamano = false
                    }
                    return
                }
                destino = Qt.point(
                    Math.max(0, Math.min(layout.width - contenedor.width, inicio.x + actual.x - inicioCursor.x)),
                    Math.max(0, Math.min(layout.height - contenedor.height, inicio.y + actual.y - inicioCursor.y))
                )
            }
        property ParallelAnimation animacion: ParallelAnimation {
            id: colocar
            PropertyAction { target: mover.contenedor; property: "x"; value: mover.destino.x }
            PropertyAction { target: mover.contenedor; property: "y"; value: mover.destino.y }
            onFinished: {
                const contenedor = mover.contenedor
                if (!contenedor)
                    return
                contenedor.layout.positionItem(contenedor)
                contenedor.layout.save()
                contenedor.z = mover.zAnterior
                mover.contenedor = null
            }
        }
}
