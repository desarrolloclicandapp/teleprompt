# Teleprompt para iOS

Aplicacion nativa de teleprompter para iPhone/iPad, sin suscripciones y con biblioteca local. Se genera con XcodeGen y se compila en Codemagic.

## MVP implementado

- Biblioteca local persistente de guiones.
- Busqueda, orden y eliminacion.
- Editor de texto.
- Importacion de TXT, Markdown, PDF y DOCX.
- Extraccion de texto de PDF y DOCX.
- Lector a pantalla completa.
- Velocidad manual ajustable.
- Cuenta regresiva de tres segundos.
- Pausa, reinicio, progreso y posicion de lectura.
- Espejo horizontal y vertical.
- Controles con teclado o mando Bluetooth compatible.
- Conexion OAuth inicial con Google Drive.
- Boton de sincronizacion manual desde una carpeta de Drive.
- Camera y voz avanzada quedan fuera del flujo principal del MVP.

## Generar el proyecto

```bash
brew install xcodegen
xcodegen generate
```

El Bundle ID es `com.viraltia.teleprompt`. Codemagic usa `codemagic.yaml` para generar, firmar y producir el `.ipa`.

## Google Drive

La aplicacion usa `drive.file` y necesita el Client ID de iOS en `Teleprompt/Info.plist`. Para sincronizar manualmente se conecta Google Drive y se indica el ID de la carpeta. La sincronizacion bidireccional, el seguimiento de cambios y la subida de videos no forman parte del MVP.

## Configuracion de Apple

La firma requiere certificados/perfiles de Apple o una integracion de App Store Connect en Codemagic. Los archivos `.p8`, `.p12` y `.mobileprovision` estan excluidos por `.gitignore`.

