pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: control
    property bool ascendente: false
    property real inicio: 0
    property real acumulado: 0
    property int cantidad: 5
    property int unidad: 0
    property real transcurrido: 0
    property bool nuevo: true
    property real limite: 0
    property real fin: 0
    property real restante: ascendente ? 0 : duracion(Date.now())
    property bool terminado: false
    readonly property bool activo: ascendente ? inicio > 0 : fin > 0
    readonly property string texto: ascendente
        ? formato(Math.floor(transcurrido / 1000)) + "." + String(transcurrido % 1000).padStart(3, "0")
        : formato(restante)

    signal completo()

    function formato(segundos) {
        const dias = Math.floor(segundos / 86400)
        const horas = Math.floor(segundos / 3600) % 24
        const minutos = Math.floor(segundos / 60) % 60
        return (dias ? dias + " d " : "")
            + (dias || horas ? String(horas).padStart(2, "0") + ":" : "")
            + String(minutos).padStart(2, "0") + ":"
            + String(segundos % 60).padStart(2, "0")
    }

    function duracion(desde) {
        if (unidad !== 3)
            return cantidad * [60, 3600, 86400][unidad]

        const fecha = new Date(desde)
        const dia = fecha.getDate()
        fecha.setDate(1)
        fecha.setMonth(fecha.getMonth() + cantidad)
        const ultimoDia = new Date(fecha.getFullYear(), fecha.getMonth() + 1, 0).getDate()
        fecha.setDate(Math.min(dia, ultimoDia))
        return Math.ceil((fecha.getTime() - desde) / 1000)
    }

    function iniciar() {
        if (activo)
            return
        if (ascendente) {
            inicio = Date.now()
            return
        }
        const ahora = Date.now()
        if (nuevo || restante <= 0)
            restante = duracion(ahora)
        nuevo = false
        limite = restante
        terminado = false
        fin = ahora + restante * 1000
    }
    function actualizar() {
        if (!activo)
            return
        if (ascendente) {
            transcurrido = acumulado + Math.max(0, Date.now() - inicio)
            return
        }
        restante = Math.max(0, Math.min(limite, Math.ceil((fin - Date.now()) / 1000)))
        if (restante === 0) {
            fin = 0
            terminado = true
            completo()
        }
    }
    function pausar() {
        if (ascendente) {
            if (activo) {
                acumulado += Math.max(0, Date.now() - inicio)
                transcurrido = acumulado
                inicio = 0
            }
            return
        }
        actualizar()
        fin = 0
    }
    function reiniciar() {
        fin = 0
        terminado = false
        inicio = 0
        acumulado = 0
        transcurrido = 0
        nuevo = true
        restante = ascendente ? 0 : duracion(Date.now())
    }
}
