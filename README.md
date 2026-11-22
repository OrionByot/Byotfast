# Byotfast

Byotfast reúne perfiles de cierre de ventanas, lanzadores con atajos de KDE y 17 widgets para el escritorio y el panel de Plasma. Desarrollado por Orinson Tuanama.

## Capturas de pantalla
<img width="1266" height="957" alt="Captura de pantalla_20261122_121905" src="https://github.com/user-attachments/assets/9ff6c167-a6f8-43f3-81ee-345c04e6717d" />
<img width="1246" height="954" alt="Captura de pantalla_20261122_121843" src="https://github.com/user-attachments/assets/cda9ce1d-619f-445f-a9b9-99a9cf0496b5" />
<img width="1600" height="900" alt="image" src="https://github.com/user-attachments/assets/b5a65268-62a8-4bcc-a9b7-3bca97f74daa" />
<img width="1509" height="669" alt="Captura de pantalla_20261122_123059" src="https://github.com/user-attachments/assets/d1bb9f7c-5e8a-42d2-a595-1b4c912abe9d" />
<img width="530" height="326" alt="Captura de pantalla_20261122_123222" src="https://github.com/user-attachments/assets/6216985d-ffc1-4cf8-99dd-acac61bc16f1" />
<img width="639" height="226" alt="Captura de pantalla_20261122_123233" src="https://github.com/user-attachments/assets/fe7fb048-3b44-423d-a6c6-5c0a4a54779b" />
<img width="1165" height="496" alt="Captura de pantalla_20261122_123254" src="https://github.com/user-attachments/assets/b8968d62-ac3c-4af0-b8c9-c059bdf7fc6c" />
<img width="1066" height="818" alt="Captura de pantalla_20261122_121050" src="https://github.com/user-attachments/assets/8d121cae-7e96-4598-827f-2693d6134c6b" />
<img width="999" height="770" alt="Captura de pantalla_20261122_121145" src="https://github.com/user-attachments/assets/be455be4-6c55-4da0-919a-699123d5023d" />
<img width="999" height="773" alt="Captura de pantalla_20261122_121200" src="https://github.com/user-attachments/assets/dae09813-4fad-42af-94fd-a2602385c476" />
<img width="967" height="720" alt="Captura de pantalla_20261122_121233" src="https://github.com/user-attachments/assets/1f5771ed-c621-4ac6-8125-eef3d4794ca9" />
<img width="971" height="757" alt="Captura de pantalla_20261122_121816" src="https://github.com/user-attachments/assets/0cf14669-ca39-4b01-9d3a-57ac7f147dd8" />


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
