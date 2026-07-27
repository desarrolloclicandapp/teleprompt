# Teleprompt para iOS

Aplicación nativa de teleprompter para iPhone/iPad, pensada para funcionar sin suscripciones y con biblioteca local. El proyecto se genera con [XcodeGen](https://github.com/yonaskolb/XcodeGen) y se compila en Codemagic.

## Estado actual

- Biblioteca local persistente de guiones.
- Editor de texto.
- Importación de archivos `.txt` y Markdown mediante Archivos.
- Lector de teleprompter en pantalla completa.
- Velocidad y tamaño de texto configurables.
- Espejo horizontal y vertical.
- Cuenta base preparada para sincronización con una carpeta externa.
- `codemagic.yaml` para generar el proyecto, firmar y producir el `.ipa`.
- Núcleo de cámara frontal, grabación local y reconocimiento de voz local.
- Cliente de Drive API, OAuth PKCE y coordinador de sincronización preparados.

## Generar el proyecto

```bash
brew install xcodegen
xcodegen generate
```

Después, Codemagic puede usar el proyecto generado con el workflow incluido. La firma requiere configurar el bundle ID `com.viraltia.teleprompt`, certificados/perfiles de Apple y una conexión de App Store Connect.

## Próximos módulos

1. Google Drive API con OAuth, sincronización bidireccional y resolución de conflictos.
2. Cámara frontal y grabación local.
3. Seguimiento de voz con `SFSpeechRecognizer` y alineación de palabras.
4. Controles Bluetooth y captura de teclas multimedia.
5. Pruebas en dispositivo y refinamiento de desplazamiento de alta fluidez.

## Configuración pendiente del usuario

Google Drive ya tiene un cliente OAuth de tipo iOS asociado a `com.viraltia.teleprompt`; el Client ID está configurado en `Teleprompt/Info.plist`. Para la distribución en Codemagic también se debe usar el bundle ID `com.viraltia.teleprompt`.
