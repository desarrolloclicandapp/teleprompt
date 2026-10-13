# Servicios, compras, permisos y límites de Android

## Frontera de red

La app no tiene endpoints de negocio propios. Las únicas integraciones remotas del port serán Google Drive/autorización y Google Play Billing. Guiones, preferencias y captura se procesan localmente. No crear API propia, panel web, servidor de licencias ni subida de vídeos.

## Google Drive

### Autorización

Crear configuración Android para el package y las huellas de firma correctas: debug, upload cuando corresponda y especialmente certificado de **Play App Signing** para instalaciones de Play. El Client ID iOS y su esquema de retorno no sirven para Android. Documentar qué huella usa cada variante.

Usar el flujo de [autorización Android de Google](https://developer.android.com/identity/authorization) para acceso opcional a Drive. No forzar un login al abrir el lector, ni confundir autenticación con permiso para consultar archivos. Pedir consentimiento al conectar y gestionar cancelación/reautorización/cambio de cuenta.

Preservar el scope actual `drive.readonly` si se pretende navegar/recorrer carpetas existentes con la misma cobertura. Es un scope restringido y de alcance amplio; la UI limita qué carpeta descarga la app, pero el permiso no queda técnicamente limitado a esa carpeta. Revisar verificación OAuth y obligaciones aplicables. Cambiar a `drive.file` exige rediseñar selección/acceso y no se acepta como paridad silenciosa. Ver [scopes de Drive](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

Dejar al cliente de autorización gestionar tokens cuando sea posible. No copiar automáticamente el refresh token manual de iOS ni pedir un server auth code si no habrá servidor. Si se necesita persistir un secreto, usar almacenamiento privado y Keystore. Nunca registrar tokens, correos o textos de guiones en logs.

### Contratos HTTP existentes

| Operación | Contrato actual que se debe conservar |
| --- | --- |
| Listar archivos de carpeta | `GET https://www.googleapis.com/drive/v3/files`, consulta de parent ID y `trashed=false`, filtros TXT/MD/PDF/DOCX. |
| Listar carpetas | Mismo endpoint con MIME `application/vnd.google-apps.folder`; navegar desde `root`. |
| Paginación | `nextPageToken` hasta agotarse; `pageSize=1000` en la referencia; preservar campos mínimos necesarios. |
| Metadatos | ID, name, mimeType, modifiedTime y md5Checksum cuando estén presentes; tolerar nulos. |
| Descarga | `GET /drive/v3/files/{fileID}?alt=media`, bytes para importador. |
| Autorización | Bearer temporal gestionado por el mecanismo Android. |
| Timeout de referencia | 30 segundos; cancelación adicional por salida/cambio de cuenta. |
| Escritura remota | Deshabilitada: el método iOS `upload` devuelve error. Android no lo expondrá. |

Google Docs nativos no son DOCX descargables por `alt=media`. No introducir exportaciones nuevas para ellos dentro de este port.

### Errores y sincronización

- 401: solicitar/renovar autorización una vez y reintentar; no bucle infinito.
- 403: mensaje de acceso no autorizado; no asumir siempre un problema de usuarios de prueba.
- 404: informar pérdida de archivo/carpeta y permitir volver a elegir.
- 429/5xx: reintento acotado con backoff; no bloquear lector ni perder biblioteca.
- Timeout/offline: conservar copias locales y mostrar resumen; no iniciar trial o cerrar acceso por fallo de Drive.
- Recorrido recursivo con conjunto de carpetas visitadas, límite operativo y cancelación; tratar páginas incompletas.
- Reimportar por identidad de cuenta+origen+archivo; no unir automáticamente documentos de cuentas distintas por su nombre.
- Al cambiar cuenta/carpeta, cancelar trabajo viejo y no aplicar sus resultados al estado nuevo.
- No borrar la copia local porque su archivo remoto haya desaparecido. Sincronizar puede reemplazar una edición local del mismo documento, como en iOS; probar ese contrato.

## Archivos e importadores

Emplear Storage Access Framework para documentos y árboles. `ContentResolver` abre streams; las URI `content://` no son rutas de filesystem. Guardar grants persistentes de lectura cuando existan y manejar permisos revocados. Referencia: [SAF](https://developer.android.com/guide/topics/providers/document-provider).

TXT y Markdown: UTF-8 con BOM si aparece, saltos CRLF/LF y Unicode. Markdown se conserva como texto; no introducir render HTML. Informar codificación ilegible en vez de importar basura.

DOCX: leer `word/document.xml` del ZIP, extraer texto con parser seguro y namespaces; proteger límites de expansión/entradas, no resolver entidades externas y no extraer rutas arbitrarias. Conservar párrafos y el orden de texto. El PDF de imágenes o protegido sin texto no debe dar un guion vacío como éxito.

PDF: la fase 0 debe decidir extractor compatible con minSdk y muestras reales; el renderizado de páginas y la extracción de texto son problemas diferentes. No declarar soporte completo usando solo una API de render. Revisar mantenimiento/licencia y, si el SDK incorpora `.so`, compatibilidad de ABIs y [páginas de 16 KB](https://developer.android.com/guide/practices/page-sizes).

Mantener streams cerrados, tamaños acotados, lectura fuera de UI y resumen por lote. No solicitar `MANAGE_EXTERNAL_STORAGE` ni permisos globales para el importador SAF.

## Cámara y salida a galería

CameraX es la propuesta para Preview y VideoCapture. Su `Recording` admite pause/resume/stop; usarlo en lugar de copiar automáticamente el montaje de segmentos AVFoundation. Validar límites por dispositivo y orientación. Referencia: [captura de vídeo CameraX](https://developer.android.com/media/camera/camerax/video-capture).

Preparación y cierre serializados; referenciar la captura activa y esperar Finalize antes de marcar éxito. MP4 con audio compatible y calidad elegida según capacidades; evitar añadir un menú de resoluciones que no exista en el producto.

Guardar en MediaStore con metadatos de nombre/tipo y tratamiento de salida incompleta. Para escribir medios propios en Android moderno no se requiere pedir lectura global de la galería. Revisar el resultado y que otro reproductor pueda abrirlo. Referencia: [almacenamiento de medios](https://developer.android.com/training/data-storage/shared/media).

Captura de vídeo y texto tienen vidas separadas. Pausar texto no pausa grabación. Espejos de lector no alteran salida de vídeo. Pruebas obligatorias de ambos horizontales, pausa rápida, audio/vídeo sincronizados y fallo de disco. Si hay que combinar segmentos, escoger alternativa mantenida mediante prueba técnica; no incorporar una dependencia FFmpeg abandonada por inercia.

No agregar foreground service de captura como mecanismo general. El alcance es grabar mientras se usa la app; si se plantea grabación de fondo, cambia requisitos y producto y queda fuera del plan.

## Mandos y RemotePAD

Usar eventos Android `KeyEvent`, `MotionEvent` e identificación por `InputDevice`. No trasladar números de `GCKeyCode`/HID de Apple. La API de Android describe botones, ejes y sus fuentes en [entradas de mando](https://developer.android.com/games/sdk/game-controller/controller-input).

Prueba física de las distintas modalidades del RemotePAD; guardar un perfil documentado de qué evento genera cada botón y eje. Transformar a comandos semánticos antes de ejecutar lógica. Un gamepad emparejado por el sistema no exige que la app explore BLE por sí misma.

Mantener A/B/X/Y del [inventario](01-INVENTARIO-Y-PARIDAD.md); deadzone de referencia 0,12 y repetición horizontal de velocidad cada 80 ms. Deduplicación de acciones discretas equivalente a 180 ms si el dispositivo entrega fuentes duplicadas; no suprimir los repeats que desplazan o cambian velocidad.

Reiniciar ejes a cero al desconectar. Liberar foco/callbacks al salir. No secuestrar teclado al editar ni volumen/controles multimedia fuera del lector. Evaluar MediaSession solo si el hardware realmente requiere teclas multimedia. Añadir BLE directo solo tras demostrar que el dispositivo no funciona por las vías de entrada del sistema; eso requiere permisos/pruebas adicionales.

## Google Play Billing y acceso

### Modelo comercial

Una compra de tipo `INAPP` para desbloqueo permanente, sin consumo. No crear suscripción ni producto gratuito para la prueba. Precio/moneda obtenidos desde detalles de producto de Play. El ID propuesto es `lifetime_unlock`; comprobarlo en consola antes de fijarlo.

Prueba local de siete días desde la acción de comenzar acceso, independiente de la compra. Disponible compra en Configuración durante la prueba y en el paywall tras vencimiento. No hay cobro automático.

### Flujo y errores

1. Conectar Billing y obtener detalles del producto; manejar producto ausente o tienda no disponible sin inventar precio.
2. Lanzar compra por acción del usuario; serializar lanzamientos y gestionar callbacks/reconexión.
3. `PENDING` permanece pendiente; `PURCHASED` se procesa una vez por token y producto.
4. Verificar lo posible del resultado del cliente y confirmar recepción mediante acknowledgment idempotente. Google exige ese reconocimiento dentro de tres días desde la compra completada; consultar y reintentar pendientes para evitar reembolso automático. No consumir la compra permanente.
5. Consultar compras al iniciar/volver y desde Restaurar; no tratar una respuesta fallida como colección vacía válida.

La integración cliente y sus estados están descritos en [Play Billing](https://developer.android.com/google/play/billing/integrate). Los ejemplos de prueba se documentarán aparte del acceso de producción.

### Política sin backend

Google recomienda verificar compras en un backend; aquí se respeta la decisión de no tenerlo. No incluir cuenta de servicio, private keys ni llamadas autenticadas de Developer API en el APK. Firma local cuando el flujo de SDK elegido la permita y reconciliación desde Billing reducen errores, pero no equivalen a verificar tokens en servidor. Ver [seguridad de Billing](https://developer.android.com/google/play/billing/security).

Propuesta: conservar un caché privado de compra previamente procesada para continuidad offline y reconciliarlo en la siguiente consulta exitosa. No revocar por timeout; no conceder por un simple booleano de preferencias. Una respuesta válida sin compra debe actualizar el acceso. Registrar condiciones de cuenta/caché y probar cambio de cuenta; sin backend no hay revocación instantánea garantizada estando offline.

La prueba usa UTC y máximo reloj observado para resistir retrocesos simples. Escribir cambios de reloj fuera del bucle gráfico y usar tiempo monotónico dentro de la sesión. Borrado de almacenamiento/reinstalación puede reiniciarla; no crear fingerprint invasivo ni afirmar lo contrario.

La compra iOS no se transfiere a Play. No bloquear Android pidiendo un Apple ID ni ofrecer restauración de Apple. El modelo previo de usuarios iOS gratuitos no crea un derecho Android.

## Permisos y declaraciones

| Capacidad | Android propuesto | Momento |
| --- | --- | --- |
| Drive/Billing | INTERNET; capacidad de red del SDK y configuración de tienda | Sin diálogo de permiso general de red; consentimientos propios cuando correspondan. |
| Cámara frontal | CAMERA; feature de cámara opcional (`required=false`) | Activar cámara. |
| Audio de grabación | RECORD_AUDIO | Al preparar la grabación; si se deniega, el lector permanece usable. |
| Documentos/carpeta | Grants URI SAF | Elegir documento/carpeta. |
| Guardar vídeo propio | MediaStore para minSdk propuesto | Finalizar grabación, sin pedir lectura de fotos ajenas. |
| Mando emparejado | Entrada del sistema | Solo lector activo. |
| BLE directo, si se demuestra necesario | Permisos Bluetooth apropiados por API; revisar localización en APIs antiguas | Solo en flujo explícito de búsqueda/conexión. |
| Pantalla encendida | Flag de ventana; no brillo ni wake lock de CPU permanente | Entrada/salida del lector. |

No solicitar notificaciones, ubicación, acceso a todos los archivos ni lectura de galería por defecto. Verificar el manifest fusionado de dependencias antes de entregar.
