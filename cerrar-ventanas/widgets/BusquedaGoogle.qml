pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: buscador
    required property color tinta
    required property color acento
    required property color fondo
    property bool enPanel: false
    readonly property real altoSugerenciasPanel: enPanel && lista.visible ? lista.height + 4 : 0
    property var sugerencias: []
    property var solicitud: null

    function buscar(valor) {
        const texto = valor.trim()
        if (!texto)
            return
        lista.close()
        campo.focus = false
        Qt.openUrlExternally("https://www.google.com/search?q=" + encodeURIComponent(texto))
    }

    function cancelarSugerencias() {
        espera.stop()
        const anterior = solicitud
        solicitud = null
        if (anterior)
            anterior.abort()
    }

    function consultar() {
        const texto = campo.text.trim()
        if (!campo.activeFocus || texto.length < 2)
            return
        const peticion = new XMLHttpRequest()
        solicitud = peticion
        peticion.onreadystatechange = () => {
            if (peticion.readyState !== XMLHttpRequest.DONE || buscador.solicitud !== peticion)
                return
            buscador.solicitud = null
            if (peticion.status !== 200 || campo.text.trim() !== texto || !campo.activeFocus)
                return
            try {
                const opciones = JSON.parse(peticion.responseText)[1]
                buscador.sugerencias = Array.isArray(opciones)
                    ? opciones.filter(valor => typeof valor === "string" && valor.trim()).slice(0, 6) : []
            } catch (_) {
                buscador.sugerencias = []
            }
            if (buscador.sugerencias.length)
                lista.open()
        }
        peticion.open("GET", "https://suggestqueries.google.com/complete/search?client=firefox&q=" + encodeURIComponent(texto))
        peticion.send()
    }

    Timer { id: espera; interval: 320; onTriggered: buscador.consultar() }
    Component.onDestruction: cancelarSugerencias()

    Rectangle {
        id: barra
        y: (parent.height - height - buscador.altoSugerenciasPanel) / 2
        width: parent.width
        height: 38
        radius: height / 2
        color: Qt.alpha(buscador.fondo, 0.9)
        border.color: campo.activeFocus ? buscador.acento : Qt.alpha(buscador.tinta, 0.3)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 4
            spacing: 6
            Kirigami.Icon {
                source: Qt.resolvedUrl("google-marca.svg")
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
            }
            Controls.TextField {
                id: campo
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                placeholderText: "Buscar…"
                Accessible.name: "Buscar en Google"
                color: buscador.tinta
                placeholderTextColor: Qt.alpha(buscador.tinta, 0.7)
                background: Item {}
                selectByMouse: true
                maximumLength: 180
                onTextEdited: {
                    buscador.cancelarSugerencias()
                    lista.close()
                    buscador.sugerencias = []
                    espera.restart()
                }
                onActiveFocusChanged: if (!activeFocus) buscador.cancelarSugerencias()
                onAccepted: buscador.buscar(lista.visible && resultados.currentIndex >= 0
                    ? buscador.sugerencias[resultados.currentIndex] : text)
                Keys.onDownPressed: if (lista.visible) resultados.currentIndex = Math.min(resultados.count - 1, resultados.currentIndex + 1)
                Keys.onUpPressed: if (lista.visible) resultados.currentIndex = Math.max(-1, resultados.currentIndex - 1)
                Keys.onEscapePressed: {
                    buscador.cancelarSugerencias()
                    lista.close()
                }
            }
            Controls.ToolButton {
                icon.name: "system-search-symbolic"
                Accessible.name: "Buscar"
                onClicked: buscador.buscar(campo.text)
            }
        }
    }

    Controls.Popup {
        id: lista
        parent: barra
        x: 0
        y: barra.height + 4
        width: barra.width
        height: resultados.count * 32 + 8
        padding: 4
        popupType: Controls.Popup.Item
        focus: false
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
        onOpened: resultados.currentIndex = -1
        background: Rectangle {
            color: buscador.fondo
            radius: 10
            border.color: Qt.alpha(buscador.tinta, 0.25)
        }
        contentItem: ListView {
            id: resultados
            clip: true
            interactive: false
            model: buscador.sugerencias
            delegate: Controls.ItemDelegate {
                required property string modelData
                required property int index
                width: resultados.width
                height: 32
                text: modelData
                highlighted: hovered || resultados.currentIndex === index
                onClicked: buscador.buscar(modelData)
            }
        }
    }
}
