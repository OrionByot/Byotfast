pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.Effects as Effects
import org.kde.kirigami as Kirigami

Controls.ScrollView {
    id: tarjeta
    required property DatosWidgets modelo
    required property color tinta
    required property color acento
    property string errorCalculo: ""
    property bool enPanel: false
    property int pagina: 0
    readonly property var elementosPaginados: {
        if (!enPanel)
            return []
        switch (tipo) {
        case "tareas": return modelo.tareas
        case "bateria": return datos.dispositivos || []
        case "discos": return datos.unidades || []
        case "clima": return segundaVista ? datos.horas || [] : modelo.ciudades
        case "calculadora": return segundaVista ? modelo.historial : []
        default: return []
        }
    }
    readonly property int porPagina: tipo === "tareas" ? 1 : tipo === "clima" && segundaVista ? 4 : 2
    readonly property int paginas: Math.max(1, Math.ceil(elementosPaginados.length / porPagina))
    readonly property int paginaActual: Math.min(pagina, paginas - 1)
    function paginaDe(elementos) {
        return enPanel ? elementos.slice(paginaActual * porPagina, (paginaActual + 1) * porPagina) : elementos
    }

    property bool segundaVista: false
    property real proporcion: height > 0 ? width / height : 1
    readonly property bool horizontal: proporcion >= 1.2
    readonly property bool vertical: proporcion <= 0.82
    signal volverVistaPrincipal()

    onSegundaVistaChanged: {
        pagina = 0
        const desplazamiento = contentItem as Flickable
        if (desplazamiento)
            desplazamiento.contentY = desplazamiento.originY
    }
    readonly property var datos: modelo.estado
    readonly property string tipo: modelo.tipo

    clip: true
    contentWidth: availableWidth
    Binding on contentHeight {
        when: tarjeta.tipo === "musica" || tarjeta.enPanel
        value: tarjeta.availableHeight
    }
    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
    Controls.ScrollBar.vertical.policy: enPanel || tipo === "clima" || tipo === "calculadora" || tipo === "musica"
        ? Controls.ScrollBar.AlwaysOff : Controls.ScrollBar.AsNeeded

    function resolver() {
        if (!operacion.text.trim())
            return
        try {
            const resultado = modelo.calcular(operacion.text)
            modelo.registrar(operacion.text, resultado)
            operacion.text = resultado
            errorCalculo = ""
        } catch (error) {
            errorCalculo = error.message
        }
    }

    component Etiqueta: Controls.Label {
        color: tarjeta.tinta
        textFormat: Text.PlainText
    }

    component Accion: Controls.Button {
        id: boton
        property bool principal: false
        implicitHeight: 29
        leftPadding: 6
        rightPadding: 6
        contentItem: Text {
            text: boton.text
            textFormat: Text.PlainText
            color: tarjeta.tinta
            opacity: boton.enabled ? 1 : 0.45
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 6
            color: Qt.alpha(tarjeta.acento, boton.down ? 0.45 : boton.principal || boton.hovered ? 0.30 : 0.15)
            border.color: Qt.alpha(tarjeta.acento, boton.visualFocus ? 1 : 0.28)
        }
    }

    component Campo: Controls.TextField {
        color: tarjeta.tinta
        placeholderTextColor: Qt.alpha(tarjeta.tinta, 0.62)
        Layout.fillWidth: true
        Layout.minimumWidth: 40
        background: Rectangle {
            radius: 6
            color: Qt.alpha(tarjeta.tinta, 0.07)
            border.color: Qt.alpha(tarjeta.acento, 0.45)
        }
    }

    component MedidaCompacta: ColumnLayout {
        id: medida
        required property real nivel
        required property string nombre
        property string resumen: ""
        property string detalle: ""
        property bool mostrarRayo: false
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Layout.minimumWidth: 0
        spacing: 2

        Controls.ToolTip.visible: cursor.hovered && !!detalle
        Controls.ToolTip.delay: 550
        Controls.ToolTip.text: detalle
        HoverHandler { id: cursor }

        Anillo {
            Layout.alignment: Qt.AlignHCenter
            nivel: medida.nivel
            tinta: tarjeta.tinta
            acento: tarjeta.acento
            mostrarRayo: medida.mostrarRayo
            Accessible.name: medida.nombre + ", " + Math.round(nivel) + "%"
        }
        Etiqueta {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            id: nombreMedida
            Layout.minimumWidth: 0
            font.bold: true
            text: !tarjeta.enPanel && medidaNombre.advanceWidth > nombreMedida.width
                ? medida.nombre.trim().split(/\s+/)[0] : medida.nombre
            Accessible.name: medida.nombre
            TextMetrics {
                id: medidaNombre
                font: nombreMedida.font
                text: medida.nombre
            }
        }
        Etiqueta {
            visible: !!text
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.pixelSize: 11
            opacity: 0.75
            text: medida.resumen
        }
    }

    ColumnLayout {
        id: contenidoTarjeta
        width: tarjeta.availableWidth
        height: tarjeta.enPanel || tarjeta.tipo === "musica" ? tarjeta.availableHeight
            : Math.max(implicitHeight, tarjeta.availableHeight)
        spacing: 0

        Item { Layout.fillHeight: true }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 7

            Etiqueta {
                visible: !!tarjeta.modelo.error
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: tarjeta.modelo.error
            }

            ColumnLayout {
                visible: tarjeta.tipo === "tareas"
                Layout.fillWidth: true
                RowLayout {
                    Campo {
                        id: tareaNueva
                        placeholderText: "Nueva tarea"
                        maximumLength: 250
                        onAccepted: agregarTarea.clicked()
                    }
                    Accion {
                        id: agregarTarea
                        text: "+"
                        Accessible.name: "Añadir tarea"
                        enabled: !!tareaNueva.text.trim()
                        principal: true
                        onClicked: {
                            tarjeta.modelo.nuevaTarea(tareaNueva.text)
                            tareaNueva.clear()
                            tareaNueva.forceActiveFocus()
                        }
                    }
                }
                Etiqueta {
                    visible: !tarjeta.modelo.tareas.length
                    text: "Todavía no hay tareas."
                }
                Repeater {
                    model: tarjeta.tipo === "tareas" ? tarjeta.paginaDe(tarjeta.modelo.tareas) : []
                    delegate: RowLayout {
                        id: filaTarea
                        required property var modelData
                        required property int index
                    readonly property int indiceReal: index + (tarjeta.enPanel ? tarjeta.paginaActual * tarjeta.porPagina : 0)
                        Layout.fillWidth: true
                        spacing: 3
                        Controls.CheckBox {
                            checked: filaTarea.modelData.hecha
                            Accessible.name: filaTarea.modelData.texto
                            onClicked: tarjeta.modelo.cambiarTarea(filaTarea.indiceReal, "marcar")
                        }
                        Etiqueta {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.strikeout: filaTarea.modelData.hecha
                            opacity: filaTarea.modelData.hecha ? 0.65 : 1
                            text: filaTarea.modelData.texto
                        }
                        Accion {
                            text: "↑"
                            Accessible.name: "Subir tarea"
                            enabled: filaTarea.indiceReal > 0
                            onClicked: tarjeta.modelo.cambiarTarea(filaTarea.indiceReal, "subir")
                        }
                        Accion {
                            text: "↓"
                            Accessible.name: "Bajar tarea"
                            enabled: filaTarea.indiceReal + 1 < tarjeta.modelo.tareas.length
                            onClicked: tarjeta.modelo.cambiarTarea(filaTarea.indiceReal, "bajar")
                        }
                        Accion {
                            text: "×"
                            Accessible.name: "Quitar tarea"
                            onClicked: tarjeta.modelo.cambiarTarea(filaTarea.indiceReal, "borrar")
                        }
                    }
                }
            }

            ColumnLayout {
                visible: tarjeta.tipo === "bateria"
                Layout.fillWidth: true
                Etiqueta {
                    visible: !tarjeta.datos.dispositivos?.length && !tarjeta.modelo.error
                    text: tarjeta.modelo.solicitud ? "Buscando baterías…" : "No se detectaron baterías."
                }
                GridLayout {
                    id: medidoresBateria
                    readonly property var pagina: tarjeta.tipo === "bateria" ? tarjeta.paginaDe(tarjeta.datos.dispositivos || []) : []
                    Layout.fillWidth: true
                    columns: tarjeta.vertical ? 1 : 2
                    uniformCellWidths: true
                    rowSpacing: 8
                    Repeater {
                        model: medidoresBateria.pagina
                        delegate: MedidaCompacta {
                            required property var modelData
                            required property int index
                            Layout.columnSpan: !tarjeta.vertical && index % 2 === 0
                                && index === medidoresBateria.pagina.length - 1 ? 2 : 1
                            readonly property string autonomia: {
                                const minutos = Math.ceil((modelData.segundos || 0) / 60)
                                return minutos >= 60 ? Math.floor(minutos / 60) + " h " + minutos % 60 + " min"
                                    : minutos > 0 ? minutos + " min" : ""
                            }
                            nivel: modelData.carga
                            nombre: modelData.principal ? "Equipo" : modelData.nombre
                            mostrarRayo: modelData.estado === "Carga completa" || modelData.estado === "Cargando"
                            resumen: modelData.estado === "Carga completa" ? ""
                                : autonomia || (mostrarRayo ? "" : modelData.estado || "")
                            detalle: [modelData.nombre, modelData.estado, autonomia,
                                modelData.vatios > 0 ? modelData.vatios + " W" : ""].filter(Boolean).join(" · ")
                        }
                    }
                }
            }

            ColumnLayout {
                id: tiempo
                visible: tarjeta.tipo === "clima"
                Layout.fillWidth: true
                property bool buscando: false
                readonly property bool mostrarBuscador: buscando || !tarjeta.modelo.ciudad.nombre

                function editarCiudad() {
                    buscando = true
                    ciudad.forceActiveFocus()
                }

                Controls.AbstractButton {
                    id: nombreCiudad
                    visible: !tarjeta.segundaVista && !tiempo.mostrarBuscador
                    Layout.fillWidth: true
                    text: tarjeta.modelo.ciudad.nombre || ""
                    padding: 2
                    hoverEnabled: true
                    Accessible.name: text
                    Accessible.description: "Cambiar ciudad"
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.delay: 500
                    Controls.ToolTip.text: text + "\nDoble clic para cambiar de ciudad"
                    background: Rectangle {
                        radius: 5
                        color: nombreCiudad.visualFocus ? Qt.alpha(tarjeta.acento, 0.18) : "transparent"
                    }
                    contentItem: Etiqueta {
                        text: nombreCiudad.text.split(",")[0]
                        font.bold: true
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                    onDoubleClicked: tiempo.editarCiudad()
                    Keys.onReturnPressed: tiempo.editarCiudad()
                    Keys.onSpacePressed: tiempo.editarCiudad()
                }
                RowLayout {
                    visible: !tarjeta.segundaVista && tiempo.mostrarBuscador
                    Campo {
                        id: ciudad
                        placeholderText: "Escribe una ciudad"
                        maximumLength: 100
                        onAccepted: buscar.clicked()
                        Keys.onEscapePressed: {
                            if (tarjeta.modelo.ciudad.nombre) {
                                tiempo.buscando = false
                                nombreCiudad.forceActiveFocus()
                            }
                        }
                    }
                    Accion {
                        id: buscar
                        text: "Buscar"
                        enabled: ciudad.text.trim().length > 1 && !tarjeta.modelo.solicitud
                        onClicked: tarjeta.modelo.ejecutar("buscar-ciudad", [ciudad.text.trim()])
                    }
                }
                Repeater {
                    model: tarjeta.tipo === "clima" && !tarjeta.segundaVista && tiempo.mostrarBuscador ? tarjeta.paginaDe(tarjeta.modelo.ciudades) : []
                    delegate: Accion {
                        id: opcionCiudad
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.nombre
                        onClicked: {
                            tarjeta.modelo.elegirCiudad(modelData)
                            tiempo.buscando = false
                        }
                    }
                }
                Etiqueta {
                    visible: !tarjeta.segundaVista && tiempo.mostrarBuscador && tarjeta.modelo.operacion === "buscar-ciudad"
                        && !tarjeta.modelo.solicitud && !tarjeta.modelo.ciudades.length && !tarjeta.modelo.error
                    text: "No se encontraron ciudades."
                }
                Etiqueta {
                    visible: !tarjeta.segundaVista && !tiempo.mostrarBuscador && tarjeta.datos.temperatura == null
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: tarjeta.modelo.solicitud ? "Consultando el clima…" : "Pronóstico no disponible."
                }
                Accion {
                    visible: !tarjeta.segundaVista && !tiempo.mostrarBuscador
                        && tarjeta.datos.temperatura == null && !tarjeta.modelo.solicitud
                    Layout.alignment: Qt.AlignHCenter
                    text: "Reintentar"
                    onClicked: tarjeta.modelo.actualizar(true)
                }
                GridLayout {
                    id: condiciones
                    visible: !tarjeta.segundaVista && !tiempo.mostrarBuscador && tarjeta.datos.temperatura != null
                    Layout.alignment: Qt.AlignHCenter
                    columns: tarjeta.horizontal ? 2 : 1
                    columnSpacing: 16
                    rowSpacing: 5

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        spacing: 1
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 6
                            Kirigami.Icon {
                                source: tarjeta.datos.icono || "org.local.Byotfast.Clima"
                                color: tarjeta.acento
                                isMask: true
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                            }
                            Etiqueta {
                                font.pixelSize: 34
                                text: (tarjeta.datos.temperatura ?? "…") + "°"
                            }
                        }
                        Etiqueta {
                            Layout.alignment: Qt.AlignHCenter
                            text: tarjeta.datos.estado || ""
                            opacity: 0.85
                        }
                    }
                    GridLayout {
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        columns: tarjeta.horizontal ? 1 : 2
                        rowSpacing: 4
                        columnSpacing: 12
                        Etiqueta { text: "Máx. " + (tarjeta.datos.maxima ?? "…") + "°" }
                        Etiqueta { text: "Mín. " + (tarjeta.datos.minima ?? "…") + "°"; opacity: 0.75 }
                    }
                }
                Etiqueta {
                    visible: tarjeta.segundaVista && !!tarjeta.datos.horas?.length
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Próximas horas · % de lluvia"
                    opacity: 0.75
                    font.pixelSize: 11
                }
                GridLayout {
                    visible: tarjeta.segundaVista && !!tarjeta.datos.horas?.length
                    Layout.fillWidth: true
                    columns: tarjeta.enPanel ? 4 : tarjeta.vertical ? 2 : 4
                    uniformCellWidths: true
                    columnSpacing: 4
                    rowSpacing: 4
                    Repeater {
                        model: tarjeta.tipo === "clima" && tarjeta.segundaVista ? tarjeta.paginaDe(tarjeta.datos.horas || []) : []
                        delegate: Rectangle {
                            id: hora
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            radius: 7
                            color: Qt.alpha(tarjeta.tinta, 0.065)
                            Accessible.name: modelData.hora + ", " + modelData.temperatura + " grados"
                                + (modelData.lluvia != null ? ", lluvia " + modelData.lluvia + "%" : "")
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 1
                                Etiqueta { Layout.alignment: Qt.AlignHCenter; text: hora.modelData.hora; font.pixelSize: 11; opacity: 0.72 }
                                Etiqueta { Layout.alignment: Qt.AlignHCenter; text: hora.modelData.temperatura + "°"; font.bold: true }
                                Etiqueta {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: hora.modelData.lluvia != null ? hora.modelData.lluvia + "%" : "—"
                                    color: tarjeta.acento
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
                Etiqueta {
                    visible: tarjeta.segundaVista && !tarjeta.datos.horas?.length && !tarjeta.modelo.error
                    text: tarjeta.modelo.ciudad.nombre ? "Pronóstico aún no disponible." : "Elige una ciudad en la vista del clima."
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }

            ColumnLayout {
                id: musica
                visible: tarjeta.tipo === "musica"
                readonly property var pista: tarjeta.modelo.musicaVisible
                property real ahora: Date.now()
                readonly property real posicion: tarjeta.modelo.posicionMusica(ahora)
                readonly property bool tresColumnas: tarjeta.horizontal && tarjeta.availableWidth >= 330
                readonly property real escala: {
                    const altoBase = tresColumnas ? 92 : tarjeta.vertical ? 177 : tarjeta.horizontal ? 122 : 132
                    const alto = tarjeta.availableHeight - (tarjeta.modelo.error ? 24 : 0)
                    return Math.min(1.15, Math.max(0.58, alto / altoBase))
                }
                Layout.fillWidth: true

                Timer {
                    interval: 500
                    running: musica.visible && tarjeta.datos.sonando === true && musica.pista.duracion > 0
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: musica.ahora = Date.now()
                }

                function tiempo(microsegundos) {
                    const segundos = Math.floor(microsegundos / 1000000)
                    return Math.floor(segundos / 60) + ":" + String(segundos % 60).padStart(2, "0")
                }
                Etiqueta {
                    visible: !musica.pista.reproductor && !tarjeta.modelo.error
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Abre un reproductor compatible con MPRIS."
                }
                GridLayout {
                    visible: !!musica.pista.reproductor
                    Layout.fillWidth: true
                    Layout.maximumWidth: Math.min(tarjeta.availableWidth, (musica.tresColumnas ? 430 : tarjeta.horizontal ? 292 : 220) * musica.escala)
                    Layout.alignment: Qt.AlignHCenter
                    columns: musica.tresColumnas ? 3 : tarjeta.vertical ? 1 : 2
                    rowSpacing: 5 * musica.escala
                    columnSpacing: 10 * musica.escala
                    Rectangle {
                        id: marcoPortada
                        Layout.row: 0
                        Layout.column: 0
                        Layout.rowSpan: tarjeta.horizontal && !musica.tresColumnas ? 2 : 1
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        Layout.preferredWidth: (tarjeta.horizontal ? 70 : 57) * musica.escala
                        Layout.preferredHeight: Layout.preferredWidth
                        radius: width / 2
                        color: Qt.alpha(tarjeta.acento, 0.17)
                        Kirigami.Icon {
                            visible: portada.status !== Image.Ready
                            anchors.centerIn: parent
                            width: 28 * musica.escala
                            height: width
                            source: "org.local.Byotfast.Musica"
                            color: tarjeta.acento
                            isMask: true
                        }
                        Image {
                            id: portada
                            source: musica.pista.portada || ""
                            anchors.fill: parent
                            visible: status === Image.Ready
                            asynchronous: true
                            sourceSize.width: 168
                            sourceSize.height: 168
                            fillMode: Image.PreserveAspectCrop
                            layer.enabled: visible
                            layer.effect: Effects.MultiEffect {
                                maskEnabled: true
                                maskSource: mascaraPortada
                            }
                        }
                        Rectangle {
                            id: mascaraPortada
                            anchors.fill: parent
                            radius: marcoPortada.radius
                            visible: false
                            antialiasing: true
                            layer.enabled: portada.visible
                        }
                    }
                    ColumnLayout {
                        Layout.row: tarjeta.vertical ? 1 : 0
                        Layout.column: tarjeta.vertical ? 0 : 1
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2 * musica.escala
                        Etiqueta {
                            Layout.fillWidth: true
                            font.bold: true
                            font.pixelSize: Math.max(12, Math.round(14 * musica.escala))
                            elide: Text.ElideRight
                            horizontalAlignment: tarjeta.vertical ? Text.AlignHCenter : Text.AlignLeft
                            text: musica.pista.titulo || ""
                        }
                        Etiqueta {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            horizontalAlignment: tarjeta.vertical ? Text.AlignHCenter : Text.AlignLeft
                            font.pixelSize: Math.max(11, Math.round(12 * musica.escala))
                            text: musica.pista.artista || ""
                        }
                        Etiqueta {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            opacity: 0.65
                            font.pixelSize: Math.max(11, Math.round(10 * musica.escala))
                            horizontalAlignment: tarjeta.vertical ? Text.AlignHCenter : Text.AlignLeft
                            text: musica.pista.album && musica.pista.album !== musica.pista.titulo
                                ? musica.pista.album : ""
                            visible: !!text
                        }
                    }
                    GridLayout {
                        Layout.row: musica.tresColumnas ? 0 : tarjeta.vertical ? 2 : 1
                        Layout.column: musica.tresColumnas ? 2 : tarjeta.horizontal ? 1 : 0
                        Layout.columnSpan: tarjeta.horizontal || tarjeta.vertical ? 1 : 2
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        columns: 1
                        rowSpacing: 4 * musica.escala
                        RowLayout {
                            id: botonesMusicales
                            Layout.row: tarjeta.vertical || (tarjeta.horizontal && !musica.tresColumnas) ? 1 : 0
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 5 * musica.escala
                            Repeater {
                                model: tarjeta.tipo === "musica" ? ["Anterior", "Reproducir", "Siguiente"] : []
                                delegate: Accion {
                                    id: controlMusical
                                    required property string modelData
                                    principal: modelData === "Reproducir"
                                    Layout.preferredWidth: (principal ? 40 : 31) * musica.escala
                                    Layout.preferredHeight: (principal ? 36 : 29) * musica.escala
                                    Accessible.name: !principal ? modelData : tarjeta.datos.sonando ? "Pausar"
                                        : !tarjeta.datos.destino ? "Volver a abrir " + musica.pista.reproductor : "Reproducir"
                                    enabled: {
                                        if (principal)
                                            return tarjeta.datos.destino ? !!tarjeta.datos.puedeReproducir : !!musica.pista.aplicacion
                                        return modelData === "Anterior" ? !!tarjeta.datos.puedeAnterior : !!tarjeta.datos.puedeSiguiente
                                    }
                                    background: Rectangle {
                                        radius: 20
                                        color: controlMusical.principal || controlMusical.hovered || controlMusical.visualFocus
                                            ? Qt.alpha(tarjeta.acento, controlMusical.down ? 0.55 : 0.35) : "transparent"
                                    }
                                    contentItem: Item {
                                        IconoMedia {
                                            anchors.centerIn: parent
                                            width: (controlMusical.principal ? 20 : 16) * musica.escala
                                            height: width
                                            accion: controlMusical.modelData
                                            sonando: !!tarjeta.datos.sonando
                                            tinta: tarjeta.tinta
                                            opacity: controlMusical.enabled ? 1 : 0.35
                                        }
                                    }
                                    onClicked: tarjeta.modelo.controlarMusica(modelData)
                                }
                            }
                        }
                        Rectangle {
                            id: progresoMusical
                            visible: musica.posicion >= 0
                            Layout.row: botonesMusicales.Layout.row === 0 ? 1 : 0
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            Layout.maximumWidth: botonesMusicales.implicitWidth
                            Layout.preferredHeight: Math.max(2, 4 * musica.escala)
                            radius: height / 2
                            color: Qt.alpha(tarjeta.tinta, 0.18)
                            Accessible.name: "Progreso de reproducción"
                            Accessible.description: musica.tiempo(musica.posicion) + " de " + musica.tiempo(musica.pista.duracion)
                            Controls.ToolTip.visible: cursorProgreso.hovered
                            Controls.ToolTip.text: musica.tiempo(musica.posicion) + " / " + musica.tiempo(musica.pista.duracion)
                            HoverHandler { id: cursorProgreso }
                            Rectangle {
                                width: progresoMusical.width * (musica.posicion >= 0 ? musica.posicion / musica.pista.duracion : 0)
                                height: progresoMusical.height
                                radius: progresoMusical.radius
                                color: tarjeta.acento
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                visible: tarjeta.tipo === "discos"
                Layout.fillWidth: true
                Etiqueta {
                    visible: !tarjeta.datos.unidades?.length && !tarjeta.modelo.error
                    text: tarjeta.modelo.solicitud ? "Consultando discos…" : "No hay unidades disponibles."
                }
                GridLayout {
                    id: medidoresDiscos
                    readonly property var pagina: tarjeta.tipo === "discos" ? tarjeta.paginaDe(tarjeta.datos.unidades || []) : []
                    Layout.fillWidth: true
                    columns: tarjeta.vertical ? 1 : 2
                    uniformCellWidths: true
                    rowSpacing: 8
                    Repeater {
                        model: medidoresDiscos.pagina
                        delegate: MedidaCompacta {
                            required property var modelData
                            required property int index
                            Layout.columnSpan: !tarjeta.vertical && index % 2 === 0
                                && index === medidoresDiscos.pagina.length - 1 ? 2 : 1
                            nivel: 100 - modelData.uso
                            nombre: modelData.ruta
                            resumen: modelData.libre + " libres"
                            detalle: modelData.ruta + " · " + modelData.libre + " libres de " + modelData.total
                        }
                    }
                }
            }

            ColumnLayout {
                id: calculadora
                visible: tarjeta.tipo === "calculadora"
                Layout.fillWidth: true
                readonly property bool compacta: tarjeta.enPanel || tarjeta.height < 185
                spacing: compacta ? 3 : 6
                RowLayout {
                    visible: !tarjeta.segundaVista
                    Campo {
                        id: operacion
                        placeholderText: "0"
                        maximumLength: 160
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: calculadora.compacta ? 14 : 18
                        Layout.preferredHeight: calculadora.compacta ? 21 : implicitHeight
                        onAccepted: tarjeta.resolver()
                    }
                    Accion {
                        text: "Copiar"
                        Layout.preferredHeight: calculadora.compacta ? 21 : implicitHeight
                        enabled: !!operacion.text
                        onClicked: {
                            operacion.selectAll()
                            operacion.copy()
                            operacion.deselect()
                        }
                    }
                }
                Etiqueta {
                    visible: !tarjeta.segundaVista && !!tarjeta.errorCalculo
                    text: tarjeta.errorCalculo
                }
                GridLayout {
                    visible: !tarjeta.segundaVista
                    Layout.fillWidth: true
                    columns: 4
                    uniformCellWidths: true
                    rowSpacing: calculadora.compacta ? 2 : 5
                    Repeater {
                        model: tarjeta.tipo === "calculadora" ? ["C", "(", ")", "⌫", "7", "8", "9", "÷",
                            "4", "5", "6", "×", "1", "2", "3", "−", "0", ".", "=", "+"] : []
                        delegate: Accion {
                            required property string modelData
                            Layout.fillWidth: true
                            text: modelData
                            principal: modelData === "="
                            Layout.preferredHeight: calculadora.compacta ? 19 : implicitHeight
                            onClicked: {
                                if (modelData === "=") {
                                    tarjeta.resolver()
                                } else if (modelData === "C") {
                                    operacion.clear()
                                    tarjeta.errorCalculo = ""
                                } else if (modelData === "⌫") {
                                    const inicio = operacion.selectionStart
                                    const fin = operacion.selectionEnd
                                    operacion.remove(inicio === fin ? Math.max(0, fin - 1) : inicio, fin)
                                } else {
                                    const inicio = operacion.selectionStart
                                    operacion.remove(inicio, operacion.selectionEnd)
                                    operacion.insert(inicio, modelData)
                                }
                            }
                        }
                    }
                }
                Etiqueta {
                    visible: tarjeta.segundaVista
                    text: tarjeta.modelo.historial.length ? "Historial" : "Todavía no hay cálculos en el historial."
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: tarjeta.tipo === "calculadora" && tarjeta.segundaVista ? tarjeta.paginaDe(tarjeta.modelo.historial) : []
                    delegate: Accion {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.expresion + " = " + modelData.resultado
                        onClicked: {
                            operacion.text = modelData.resultado
                            tarjeta.volverVistaPrincipal()
                            operacion.forceActiveFocus()
                        }
                    }
                }
            }
        }
        RowLayout {
            visible: tarjeta.paginas > 1
            Layout.alignment: Qt.AlignHCenter
            Controls.ToolButton {
                icon.name: "go-previous-symbolic"
                Accessible.name: "Página anterior"
                enabled: tarjeta.paginaActual > 0
                onClicked: tarjeta.pagina = tarjeta.paginaActual - 1
            }
            Etiqueta { text: (tarjeta.paginaActual + 1) + " / " + tarjeta.paginas }
            Controls.ToolButton {
                icon.name: "go-next-symbolic"
                Accessible.name: "Página siguiente"
                enabled: tarjeta.paginaActual + 1 < tarjeta.paginas
                onClicked: tarjeta.pagina = tarjeta.paginaActual + 1
            }
        }
        Item { Layout.fillHeight: true }
    }
}
