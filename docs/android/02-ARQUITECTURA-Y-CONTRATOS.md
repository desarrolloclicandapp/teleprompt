# Arquitectura y contratos Android

## Estructura propuesta

Crear un proyecto Gradle autónomo bajo `android/`, con un módulo `app` inicial y paquetes por responsabilidad. No separar en múltiples módulos hasta que un problema concreto lo justifique.

```text
android/
  settings.gradle.kts
  build.gradle.kts
  gradle.properties
  gradle/libs.versions.toml
  gradlew / gradlew.bat / gradle/wrapper/
  app/
    build.gradle.kts
    proguard-rules.pro
    src/main/
      AndroidManifest.xml
      java/com/viraltia/teleprompt/
        TelepromptApplication.kt
        MainActivity.kt
        domain/{model,reader,access}/
        data/{local,repository,preferences,files,import,drive,camera,remote,billing,security}/
        ui/{navigation,theme,library,editor,reader,camera,settings,access,privacy}/
      res/{values,values-en,drawable,mipmap-*,xml}/
    src/debug/       # diagnósticos y control de reloj para pruebas
    src/test/        # lógica y contratos puros
    src/androidTest/# UI, almacenamiento y ciclo de vida
```

Estas rutas se documentan ahora; no crear Gradle, Kotlin, XML ni binarios en esta entrega.

## Flujo de estado

Pantallas Compose → acciones → ViewModel/controlador → repositorios → estado observable. La UI no debe consultar Drive ni Billing directamente. La arquitectura declarativa y flujo unidireccional están descritos en la [documentación de Compose](https://developer.android.com/develop/ui/compose/architecture).

Dependencias por constructor; un contenedor sencillo en Application es suficiente. Usar `StateFlow` para estados de pantalla, coroutines para trabajo asíncrono y IO para documentos/red/BD. Gestionar cancelación y resultados tardíos de una cuenta o carpeta anterior.

Mantener el offset que cambia por frame cerca del renderizador; no emitir todo el estado de biblioteca, controles y cámara 120 veces por segundo. Recalcular el layout del texto solo por cambios de texto, ancho, fuente o escala del sistema.

Para el desplazamiento, usar timestamps del [frame clock de Compose](https://developer.android.com/reference/kotlin/androidx/compose/runtime/MonotonicFrameClock) y calcular deltas; reiniciar el timestamp al reactivar la sesión. DataStore conserva ajustes, mientras Room conserva documentos; no utilizar escrituras de almacenamiento para cada frame.

## Modelos de datos

| Modelo | Campos mínimos | Invariantes |
| --- | --- | --- |
| Script | `id`, `title`, `text`, `createdAt`, `updatedAt`, `sourceType`, `sourceIdentity`, `sourcePath` | UUID estable; fechas en UTC; texto completo preservado. |
| SourceIdentity | Tipo + cuenta/fuente + identificador de documento | Dos archivos con igual nombre no colisionan; Drive y SAF tienen namespaces diferentes. |
| ReaderPreferences | `speedLevel`, `baseFontSize`, `mirrorHorizontal`, `mirrorVertical`, `schemaVersion` | Nivel 1–30; defaults de iOS; escribir fuera del bucle de frames. |
| ReaderSession | Guion, offset, geometría, estado de lectura, countdown y visibilidad | Estado transitorio; una sola cuenta activa; offset acotado. |
| PanelGeometry | Ancho, alto, centro y área disponible | Ancho/alto independientes; tiradores visibles dentro de límites. |
| DriveSelection | Cuenta, carpeta ID/nombre y ruta de navegación | Vaciar selección al cambiar cuenta; no utilizar etiqueta como ID. |
| LocalFolderSelection | URI de árbol y nombre visible | Permiso de lectura recuperable; revocación no borra copias locales. |
| AccessSnapshot | Inicio/fin de prueba, reloj observado, compra local reconocida y fecha de consulta | Separado de preferencias y biblioteca; caché no equivale a verificación remota. |
| RecordingState | Estado, URI de salida y error recuperable | Una captura/finalización activa; éxito solo después de finalizar y guardar. |

Room para biblioteca y migraciones, sin `fallbackToDestructiveMigration` como estrategia de actualización. Sus componentes de entidad, DAO y base están descritos en [Room](https://developer.android.com/training/data-storage/room). DataStore para preferencias pequeñas. Evitar guardar guiones completos en un Bundle o SavedStateHandle: guardar ID y referencias, y persistir borradores en almacenamiento local.

No se incluye migración automática de `scripts.json` del iPhone. Un Android no puede acceder al contenedor iOS; el usuario podrá importar sus originales o descargarlos de Drive como ya permite el producto.

## Interfaces funcionales a implementar

| Contrato | Operaciones y resultados |
| --- | --- |
| ScriptRepository | Observar lista, obtener por UUID, guardar, eliminar, importar/upsert por origen y reset de biblioteca. Error de persistencia visible. |
| DocumentImporter | URI/stream + metadatos → título/texto o acceso denegado, vacío, ilegible, tamaño excedido. |
| LocalFolderRepository | Seleccionar, conservar permiso, listar recursivamente, desvincular y sincronizar. |
| DriveAuthorization | Cuenta elegida, autorización requerida, token temporal, desconexión y reautorización. |
| DriveApi | Listar carpetas/archivos paginados y descargar bytes; resultados de HTTP tipados. |
| SyncCoordinator | Una ejecución activa, cuenta/carpeta inmutables durante esa ejecución, conteo de éxitos/fallos, cancelación. |
| ReaderController | Play, pausa, inicio, frame, gesto, resize, cambio de velocidad y comando remoto. |
| CameraRecorder | Preparar, iniciar, pausar, reanudar, finalizar, liberar; estados y evento de archivo guardado. |
| RemoteInputRouter | Eventos Android → comandos semánticos; repetición, deduplicación y desconexión. |
| PlayBillingRepository | Disponibilidad, producto/precio, lanzamiento de compra, consulta de compras y acknowledgment. |
| AccessController | Evaluar prueba/compra/caché y gate; no borrar biblioteca por pérdida de acceso. |

Definir errores tipados de dominio; localizar el mensaje en UI. No mostrar stack traces, OAuth internals ni códigos de desarrollo como instrucciones de usuario.

## Máquinas de estado

Lectura: `Ready → CountingDown → Playing ↔ Paused`. Inicio lleva a `Ready` y offset cero; cerrar cancela tareas. Reanudar desde `Paused` no pasa por countdown. Grabar tiene estados independientes.

Grabación: `Unavailable/Idle → Preparing → Ready → Recording ↔ Paused → Finalizing → Saved/Error`. Botones repetidos en Preparing/Finalizing no crean nuevas sesiones. Guardar un vídeo no depende de que la composición del lector siga montada.

Acceso: `Loading`, `FreeNotStarted`, `FreeActive`, `FreeExpired`, `Lifetime`. Flujo de compra separado: `Idle`, `Launching`, `Pending`, `AcknowledgmentPending`, `Success`, `Cancelled`, `Error`. Una compra pendiente no desbloquea; una consulta fallida no debe presentarse como una consulta exitosa sin compras.

## Rotación, segundo plano y recuperación

- Conservar borrador, ID del guion y ajustes al recrear Activity; cancelar callbacks asociados a la instancia antigua.
- Recalcular espacio con insets, barras, recorte de cámara y ventana actual; no usar solo tamaño físico de pantalla.
- Conservar dimensiones de panel independientes y acotarlas al espacio nuevo. No volver a imponer cuadrado en horizontal.
- Para mantener paridad inicial, abrir un lector nuevo con posición inicial; preservar la sesión durante una rotación normal.
- Propuesta Android: pausar desplazamiento al perder primer plano, sin avanzar el tiempo oculto. Retorno seguro, sin salto del texto.
- Mantener pantalla encendida únicamente en el lector mediante flag de ventana/keepScreenOn; liberar al salir. No cambiar brillo.
- Grabación: no inventar funcionamiento de fondo. Finalizar de forma controlada al salir; documentar qué sucede al bloquear pantalla, rotar, perder cámara o morir el proceso.
- Rotar durante grabación requiere prueba técnica. Preferir captura continua y metadatos coherentes si el dispositivo lo permite; si no, usar segmentos/finalización explícita. No reiniciar silenciosamente ni perder lo grabado.
- Separar UI reconstruible de objetos CameraX/Billing y evitar referencias permanentes a Activities destruidas.

## Seguridad, datos y backup

Excluir tokens, cachés de licencia, registros de prueba y URIs con permisos de una restauración automática que los haga pasar por credenciales válidas en otro dispositivo. Documentar si biblioteca/ajustes se respaldan; verificar Auto Backup y transferencia entre dispositivos. Las claves Keystore pueden no sobrevivir a reinstalación/restauración: borrar secretos ilegibles y solicitar autorización nuevamente.

El borrado de datos desde Configuración elimina biblioteca y enlaces según paridad, conserva política de acceso y no borra originales de Drive/SAF ni vídeos de galería. Borrar almacenamiento desde Ajustes de Android o reinstalar sí puede perder el registro de prueba: limitación documentada, no falsa promesa de prueba irrepetible.
