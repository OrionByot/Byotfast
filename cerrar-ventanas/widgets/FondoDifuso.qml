pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects as Effects
import org.kde.kirigami as Kirigami

Loader {
    id: capa
    required property real radio
    required property Item fondo
    anchors.fill: parent
    z: -1

    sourceComponent: Effects.MultiEffect {
        width: capa.width
        height: capa.height
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 64
        maskEnabled: true
        source: ShaderEffectSource {
            id: muestra
            width: capa.width
            height: capa.height
            // Reduce la resolución de la muestra antes de suavizar sus contornos.
            textureSize: Qt.size(Math.max(1, Math.ceil(width / 6)), Math.max(1, Math.ceil(height / 6)))
            sourceItem: capa.fondo
            sourceRect: capa.fondo ? Qt.rect(
                capa.Kirigami.ScenePosition.x - capa.fondo.Kirigami.ScenePosition.x,
                capa.Kirigami.ScenePosition.y - capa.fondo.Kirigami.ScenePosition.y,
                capa.width, capa.height
            ) : Qt.rect(0, 0, 0, 0)
            live: false
            onSourceItemChanged: actualizar.restart()
            onSourceRectChanged: actualizar.restart()
            onTextureSizeChanged: actualizar.restart()
            Component.onCompleted: actualizar.start()

            Timer {
                id: actualizar
                interval: 100
                onTriggered: muestra.scheduleUpdate()
            }

            Timer {
                interval: 10000
                running: capa.visible && !!muestra.sourceItem
                repeat: true
                onTriggered: muestra.scheduleUpdate()
            }
            visible: false
        }
        maskSource: Rectangle {
            width: capa.width
            height: capa.height
            radius: capa.radio
            antialiasing: true
            visible: false
            layer.enabled: true
        }
    }
}
