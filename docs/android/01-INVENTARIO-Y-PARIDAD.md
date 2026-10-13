# Inventario del código iOS y equivalencias Android

Todas las rutas de la primera columna existen en la base revisada. Las rutas de destino son propuestas dentro de `android/app/src/main/java/com/viraltia/teleprompt/`.

## Qué reutilizar y qué adaptar

| Referencia iOS | Destino Android propuesto | Trabajo y verificación |
| --- | --- | --- |
| `Teleprompt/TelepromptApp.swift` | `TelepromptApplication.kt`, `MainActivity.kt`, `ui/navigation/AppNavigation.kt` | Inicialización, repositorios y gate de acceso; apertura sin duplicar cargas. |
| `Models/Script.swift` | `domain/model/Script.kt`, `data/local/ScriptEntity.kt` | UUID, título, contenido, fechas y origen; eliminar dependencia de bookmark Apple. |
| `Stores/ScriptLibrary.swift` | `data/local/ScriptDao.kt`, `TelepromptDatabase.kt`, `data/repository/ScriptRepository.kt` | Persistencia con Room, orden, deduplicación y recuperación; conservar UUID en reimportaciones. |
| `Views/RootView.swift` | `ui/library/LibraryScreen.kt`, `LibraryViewModel.kt` | Búsqueda de título/texto, grupos, borrado, estados vacíos y selección. |
| `Views/ScriptEditorView.swift` | `ui/editor/EditorScreen.kt`, `EditorViewModel.kt` | Guardado al salir/leer y preservación de borrador en rotaciones. |
| `Views/SettingsView.swift` | `ui/settings/SettingsScreen.kt`, `SettingsViewModel.kt` | Drive, carpeta local, compras, privacidad y eliminación de datos con confirmación. |
| `Views/TeleprompterView.swift` | `ui/reader/ReaderScreen.kt`, `ReaderViewModel.kt` | Estado de lectura, límites de velocidad y preferencias. |
| `Views/TeleprompterView+Body.swift` | `ui/reader/ReaderScreen.kt`, `ReaderLifecycle.kt` | Capas, preview, controles y bloqueo de suspensión; separación entre UI y captura. |
| `Views/TeleprompterView+Controls.swift` | `ui/reader/ReaderControls.kt`, `ReaderPanel.kt` | Botones, slider, progreso, gestos de texto, movimiento y resize. |
| `Views/TeleprompterView+Layout.swift` | `domain/reader/PanelGeometry.kt` | Coordenadas, límites por orientación y región de cámara; ancho y alto independientes. |
| `Views/TeleprompterView+Remote.swift` | `domain/reader/ReaderReducer.kt`, `data/remote/RemoteInputRouter.kt` | Comandos semánticos, countdown, reset, repetición y entrada analógica. |
| `Views/TeleprompterSupport.swift` | `ui/reader/ReaderSettingsSheet.kt` | Ajustes de letra y espejo vinculados al estado persistente. |
| `Services/ReaderScrollMotion.swift` | `domain/reader/ReaderScrollMotion.kt` | Trasladar fórmulas y pruebas de invariancia temporal. |
| `Services/DisplayLinkTicker.swift` | `ui/reader/ReaderFrameLoop.kt` | Frame clock de Compose/Choreographer y delta real; no usar Timer o delay fijo para mover texto. |
| `Services/DocumentImporter.swift` | `data/import/DocumentImporter.kt`, `TxtImporter.kt`, `DocxImporter.kt`, `PdfTextExtractor.kt` | Streams de URI, extracción fuera del hilo UI y manejo de documentos inválidos. |
| `Services/ExternalFolderAccess.swift` | `data/files/LocalFolderRepository.kt` | SAF, permisos persistentes y recorrido de subcarpetas. |
| `Services/GoogleOAuth.swift` | `data/drive/DriveAuthorization.kt` | Autorización Google específica de Android; no reutilizar client ID ni callback iOS. |
| `Services/GoogleDriveService.swift` | `data/drive/DriveApi.kt`, `DriveModels.kt` | Listados paginados, descarga de bytes, filtros y errores HTTP. |
| `Services/DriveSyncCoordinator.swift` | `data/drive/DriveSyncCoordinator.kt` | Carpeta elegida, descarga/reimportación y exclusión de ejecuciones simultáneas. |
| `Services/URLFormEncoder.swift` | Cliente HTTP del módulo `data/drive` | Encoding correcto si hay peticiones de formulario; evitar copiar código OAuth obsoleto. |
| `Services/KeychainStore.swift` | `data/security/SecureLocalStore.kt` | Almacenamiento privado con claves de Android Keystore cuando haga falta; no es equivalente exacto a Keychain. |
| `Services/CameraRecorder.swift` | `data/camera/CameraRecorder.kt`, `RecordingState.kt` | CameraX, preparación, pause/resume, finalización y guardado. |
| `Views/CameraPreview.swift` | `ui/camera/CameraPreview.kt` | PreviewView integrado en Compose, orientación y cámara frontal. |
| `Views/RecordingView.swift` | Evaluación de referencia secundaria | El flujo principal usa cámara en el lector. No duplicar una pantalla de grabación si no tiene navegación de uso actual. |
| `Views/RemoteKeyCapture.swift` | `data/remote/KeyInputAdapter.kt` | KeyEvent, repeat y foco del lector; los códigos numéricos HID de Apple no son códigos Android. |
| `Views/RemoteGamepadCapture.swift` | `data/remote/GamepadInputAdapter.kt` | MotionEvent, InputDevice, ejes y botones. |
| `Views/RemoteMediaCommandCapture.swift`, `Services/MediaRemoteController.swift` | `data/remote/MediaInputAdapter.kt`, router | Evaluar MediaSession únicamente si el mando lo requiere; evitar tomar controles de otras apps. |
| `Views/RemoteInputDiagnostics.swift`, `RemoteRawGamepadProbe.swift` | `debug/RemoteInputDiagnostics.kt` | Herramientas de laboratorio por variante debug; no convertirlas en función pública. |
| `Services/StoreKitConfiguration.swift` | `domain/access/AccessPolicy.kt`, `data/billing/PlayProductConfiguration.kt` | Siete días locales y único producto permanente Android. |
| `Services/PurchaseManager.swift` | `data/billing/PlayBillingRepository.kt`, `domain/access/AccessController.kt` | Consulta, compra, confirmación, restauración, pending y caché local. |
| `Views/MonetizationViews.swift` | `ui/access/AccessIntroductionScreen.kt`, `LifetimePaywallScreen.kt`, `AccessStatusSection.kt` | Pago único visible, precio localizado, restauración y compra durante prueba. |
| `Views/PrivacyPolicyView.swift` | `ui/privacy/PrivacyScreen.kt` | Adaptar menciones de Apple/Fotos/Keychain a Android, Play y galería. |
| `Resources/es.lproj`, `en.lproj` | `res/values/strings.xml`, `res/values-en/strings.xml` | Traducir formatos/plurales y permisos, sin copiar instrucciones Apple. |
| `Assets.xcassets` | `res/drawable`, `res/mipmap-*` | Exportar originales y generar icono adaptativo; revisar licencias de iconos. |
| `Info.plist`, `PrivacyInfo.xcprivacy` | `AndroidManifest.xml`, reglas de backup y ficha Data safety | Adaptación de permisos y declaraciones; no existe traducción directa de las razones de API Apple. |
| `TelepromptTests/*`, `TelepromptUITests/*` | `src/test`, `src/androidTest` | Reusar escenarios y resultados esperados, reescribir herramientas. |
| `project.yml` | Archivos Gradle propios en `android/` | XcodeGen sigue siendo exclusivo de iOS. |
| `codemagic.yaml`, `.github/workflows/ios-validation.yml` | Workflow Android separado, previsto en [06](06-CI-Y-PUBLICACION.md) | No sustituir ni mezclar secretos de Apple con los de Play. |

Las rutas abreviadas como `Views/` y `Services/` pertenecen a `Teleprompt/`.

## Comportamientos que no deben cambiar al portar

### Lectura

El nivel se transforma en velocidad mediante `round(200 + (nivel - 1) × 2800 / 29)`, limitado a niveles 1–30. La velocidad inicial es 200 y el tamaño base inicial es 26. El tamaño efectivo iOS depende del ancho del panel y se limita entre 16 y 82; usar equivalencias visuales en dp/sp, no multiplicar por densidad varias veces.

El motor actual usa `speed × 0.12 × fontScale × elapsedSeconds` para lectura y `inputY × max(200, speed) × 0.18 × fontScale × elapsedSeconds` para joystick. `fontScale` parte de tamaño efectivo / 42. Unidades Android: movimiento en dp y conversión a píxeles en la capa de render, manteniendo fracciones para evitar saltos por redondeo.

El primer Play táctil hace cuenta 3–2–1; Play tras pausa continúa inmediatamente. Play por mando evita cuenta. Inicio cancela cuenta, pausa y devuelve offset a cero. Al llegar al final, iOS mantiene el estado de reproducción; si se mueve el guion hacia arriba, vuelve a avanzar. Mantener esa semántica.

Los ajustes persistentes son velocidad, tamaño y espejos. La posición de lectura, cámara activa y grabación no se restauran como si fueran sesiones activas tras un arranque nuevo.

### Fuentes y biblioteca

Drive y carpetas locales copian contenido a la biblioteca; no editan los archivos originales. Una reimportación puede reemplazar título/texto de la copia del mismo origen. Preservar este comportamiento y probar expresamente el caso de edición local seguida de sincronización, sin inventar un sistema de versiones.

La eliminación de un archivo remoto no borra automáticamente su copia ya importada. No convertir la descarga de Drive en espejo destructivo. La identidad debe ser de origen, no el título traducido de un grupo.

### Grabación y controles

Pausa de texto y pausa de vídeo son distintas. X pausa/reanuda una grabación existente; Y inicia o finaliza; A pausa/reanuda lectura; B muestra/oculta controles. El joystick modifica lectura y velocidad. Validar botones físicos porque el modo del RemotePAD puede cambiar lo que Android recibe.

No dibujar el guion dentro del vídeo: actualmente es una capa sobre la vista previa. Espejar el texto no debe espejar accidentalmente el archivo grabado.

### Acceso

La prueba se activa mediante acción explícita y dura siete veces 24 horas; no cobra al terminar. Puede comprarse antes de que expire. Borrar guiones/desconectar fuentes no cancela compras ni reinicia esa prueba. La regla de usuarios antiguos gratuitos de iOS usa `AppTransaction.originalAppVersion`; no aplicarla a usuarios nuevos de Android.
