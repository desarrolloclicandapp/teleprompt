# Teleprompt para iOS

Aplicacion nativa de teleprompter para iPhone, sin suscripciones y con biblioteca local. Se genera con XcodeGen y se compila en Codemagic.

## Funcionalidades

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
- La cámara y la grabación son funciones opcionales del flujo principal.

## Generar el proyecto

```bash
brew install xcodegen
xcodegen generate
```

El Bundle ID es `com.viraltia.teleprompt`. Codemagic usa `codemagic.yaml` para generar, firmar y producir el `.ipa`.

## Google Drive

La aplicacion usa `drive.readonly` y necesita el Client ID de iOS en `Teleprompt/Info.plist`. Para descargar manualmente se conecta Google Drive y se indica el ID de la carpeta. La sincronizacion bidireccional, el seguimiento de cambios y la subida de videos no están incluidos en esta versión.

## Monetizacion StoreKit 2

La app usa StoreKit 2 con un Non-Consumable gratuito de prueba y un Non-Consumable de desbloqueo permanente. Los IDs se centralizan en Teleprompt/Services/StoreKitConfiguration.swift:

- com.APP.trial7days: prueba gratuita de 7 días, Price Tier 0.
- com.APP.lifetime: desbloqueo permanente, con precio definido en App Store Connect.

El trial se inicia con la transacción verificada del producto gratuito y dura exactamente 7 x 24 horas desde Transaction.purchaseDate. La transacción de StoreKit es la fuente principal y la fecha/cache en Keychain solo permite continuidad offline y evita retrocesos simples del reloj. El proyecto no tiene backend, por lo que no se añadió DeviceCheck server-side.

Los usuarios que instalaron la app antes del cambio de modelo se identifican mediante AppTransaction.originalAppVersion en producción. El límite está en StoreKitConfiguration.lastFreeAppVersion y debe coincidir con la última versión de marketing publicada gratuitamente antes de activar monetización. La versión de esta entrega debe ser superior a ese límite.

Para probar la expiración sin esperar siete días, agrega en los argumentos de lanzamiento de Xcode (solo Debug):

    -teleprompt.trialDaysElapsed 7

Para comenzar de cero en una prueba local, usa también:

    -teleprompt.resetLocalMonetization

El archivo Teleprompt.storekit está asociado al scheme por project.yml y permite probar los dos productos localmente.

## Configuracion de Apple

La firma requiere certificados/perfiles de Apple o una integracion de App Store Connect en Codemagic. Los archivos `.p8`, `.p12` y `.mobileprovision` estan excluidos por `.gitignore`.

## Idiomas

La interfaz está localizada en español e inglés mediante los recursos de `Teleprompt/Resources`. El español es el idioma base; los textos de permisos de iOS también tienen traducciones localizadas.
