# Byotfast

Byotfast reúne perfiles de cierre de ventanas, lanzadores con atajos de KDE y 17 widgets para el escritorio y el panel de Plasma. Desarrollado por Orinson Tuanama.

## Instalar en KDE Plasma

Extrae el ZIP, entra en la carpeta `Byotfast` y ejecuta el instalador desde una terminal de tu sesión gráfica.

```bash
bash instalar-byotfast.run
```

La instalación se hace para tu usuario. Abre **Aplicaciones → Utilidades → Byotfast**. Si actualizas una instalación con widgets activos, el instalador intenta recargar Plasma para aplicar los cambios.

El entorno de referencia es Linux con KDE Plasma 6 en Wayland, KWin, D-Bus, qdbus6, Qt Quick y los módulos QML de Plasma. Los emergentes usan Qt 6.8 o posterior. La interfaz de ajustes utiliza Python 3.10 o posterior, PyGObject, GTK 4 y libadwaita con ToolbarView (1.4 o posterior). Algunas funciones requieren servicios adicionales, como NetworkManager para Wi-Fi, BlueZ para Bluetooth, WirePlumber para audio y un reproductor compatible con MPRIS.

## Editar y reconstruir

El código de la aplicación está en `cerrar-ventanas/`. La carpeta `cerrar-ventanas/widgets/` contiene los componentes QML, los iconos, los metadatos del catálogo y el esquema de configuración. Las pruebas de interfaz se encuentran en `pruebas/`.

Después de cambiar el código, regenera el instalador desde la raíz del proyecto. El script utiliza Bash, GNU tar, gzip y base64.

```bash
bash herramientas/generar-instalador.sh
```

El resultado queda en `instalar-byotfast.run`.

## Subir a GitHub

Usa el contenido de la carpeta extraída como raíz del repositorio, de modo que este README y el instalador aparezcan en la portada. Puedes adjuntar el instalador a una Release para que los usuarios descarguen directamente el archivo ejecutable.
