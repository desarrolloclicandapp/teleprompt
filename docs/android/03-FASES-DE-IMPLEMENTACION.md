# Fases, archivos y condiciones de cierre

Las casillas son tareas pendientes. El orden permite probar los componentes de riesgo antes de conectar toda la aplicación. No ejecutar estas tareas durante la entrega documental.

## Fase 0 — Cerrar decisiones y probar viabilidad

- [ ] Confirmar stack, minSdk, identificador, cuenta Play, producto y dispositivos de prueba del [plan general](00-PLAN-ANDROID.md).
- [ ] Registrar versiones estables compatibles de Kotlin, AGP, Gradle/JDK, Compose, Room, DataStore, CameraX y Billing; fijarlas sin versiones `+`.
- [ ] Probar texto largo con frame clock en teléfono 60 Hz y otro de alta frecuencia, también grabando.
- [ ] Probar extracción de PDF textual en la versión mínima: `PdfRenderer` no es un sustituto universal de PDFKit para extraer texto. Evaluar APIs según nivel Android o biblioteca y licencia; decidir antes de prometer PDF completo.
- [ ] Probar DOCX en ZIP/XML con namespaces, párrafos, tabulaciones y documentos corruptos.
- [ ] Verificar pause/resume CameraX, salida MediaStore y orientación en un dispositivo real.
- [ ] Reservar configuración de consola, firma/OAuth y prueba de producto Billing en un prototipo aislado.
- [ ] Capturar eventos del RemotePAD en su modo Android; no deducir códigos desde iOS.

Salida: decisiones registradas, muestras de prueba y riesgos resueltos o con alternativa concreta. Si falla un componente obligatorio, no presentar una beta equivalente.

## Fase 1 — Proyecto y base de UI

Archivos: raíz Gradle en `android/`, módulo `app`, Application, Activity, navegación, tema, `AndroidManifest.xml`, recursos ES/EN y variantes debug/release.

- [ ] Establecer tema oscuro, identidad, icono y equivalentes de controles existentes.
- [ ] Crear rutas biblioteca, editor, lector, configuración y acceso; no añadir login propio.
- [ ] Incluir SDKs necesarios y permisos por función, sin pedirlos al iniciar.
- [ ] Ajustar barras/insets, teclado, Back y rotación.
- [ ] Crear workflow de validación Android independiente según [06](06-CI-Y-PUBLICACION.md).

Cierre: APK debug instalable en Windows/ADB, navegación accesible, release compila y no se modifica ningún archivo Swift.

## Fase 2 — Biblioteca, editor y preferencias

Archivos: `domain/model/Script.kt`, Room Entity/DAO/Database, ScriptRepository, Library/Editor/Settings ViewModels y repositorio de preferencias.

- [ ] Implementar creación interna/seed, edición, guardado, búsqueda, orden y grupos con IDs estables.
- [ ] Conservar UUID/fecha inicial y actualizar fecha de modificación al guardar.
- [ ] Probar cierre de editor, apertura del lector, teclado y proceso interrumpido sin pérdida de borrador.
- [ ] Persistir nivel de velocidad, tamaño y espejos; restaurar antes de dibujar el lector.
- [ ] Implementar eliminación de datos con confirmación y frontera de acceso separada.
- [ ] Diseñar migraciones de BD y tratamiento de errores de disco; no resetear datos silenciosamente.

Cierre: biblioteca funciona sin red después de cerrar/reabrir; ajustes conservados; borrar datos locales no reinicia acceso.

## Fase 3 — Importación y carpetas locales

Archivos: DocumentImporter y adaptadores TXT/MD/PDF/DOCX, LocalFolderRepository, selección SAF y mensajes de sincronización.

- [ ] Selección múltiple de documentos y URI de árbol; permisos de lectura persistentes cuando el proveedor los admita.
- [ ] Copiar texto a biblioteca; no depender de rutas absolutas ni acceso continuo al archivo original.
- [ ] Detección por MIME/extensión, extracción y fallos por archivo; informar resumen parcial.
- [ ] Recorrer subcarpetas sin bucles, deduplicar por identidad y evitar bloquear UI.
- [ ] Definir límites de bytes/páginas/expansión ZIP basados en las muestras de fase 0.
- [ ] Tratar revocación, proveedor remoto offline, archivos renombrados y falta de espacio.

Cierre: cuatro formatos obligatorios, reimportación sin duplicados y lectura de las copias sin fuente disponible. PDF escaneado sin texto muestra una limitación; no añadir OCR.

## Fase 4 — Lector y rendimiento

Archivos: ReaderScreen, ReaderControls, ReaderSettingsSheet, ReaderPanel, ReaderFrameLoop, ReaderReducer, ReaderScrollMotion y PanelGeometry.

- [ ] Implementar reglas exactas de [paridad](01-INVENTARIO-Y-PARIDAD.md): 30 niveles, 200–3000, countdown inicial, reanudar, Inicio y fin.
- [ ] Renderizar texto con fracciones de desplazamiento y tiempos del frame clock. No recalcular toda la pantalla en cada frame.
- [ ] Separar medición de texto de traslación; cachear por contenido/ancho/fuente.
- [ ] Probar guiones muy largos; si el bloque único excede memoria/textura, usar bloques medidos sin introducir saltos.
- [ ] Panel movible, resize lateral/inferior/esquina y dimensiones independientes en horizontal; límites visibles y gestos sin robar scroll.
- [ ] Preservar tamaño de fuente efectivo equivalente, espejos, pausa durante gestos según comportamiento base y progreso clamped.
- [ ] Mantener pantalla encendida, liberar al salir y pausar frame loop cuando no haya trabajo.
- [ ] Medir fluidez con y sin cámara, no inferirla de un emulador rápido.

Cierre: controles, rotación y resize sin regresiones; evidencia física de movimiento continuo según [05](05-PRUEBAS-Y-ACEPTACION.md).

## Fase 5 — Cámara y grabación

Archivos: CameraRecorder, RecordingState, CameraPreview y repositorio de salida MediaStore.

- [ ] Permisos de cámara/audio bajo demanda; el lector sigue disponible si se deniegan.
- [ ] Implementar cámara frontal, inicio, pausa, reanudación y finalización idempotente.
- [ ] Confirmar orientación de preview y vídeo, audio y mirror por separado.
- [ ] Mantener texto/controles superpuestos solo en pantalla; no quemarlos en el vídeo.
- [ ] Guardar únicamente tras Finalize y éxito de persistencia; limpiar salidas incompletas y preservar archivo recuperable ante error.
- [ ] Probar repetir botones rápido, salir pausado, volver, poco almacenamiento y permisos retirados.

Cierre: vídeo reproducible con audio, secuencia de pausas correcta, sin cámaras abiertas después de cerrar ni capturas duplicadas.

## Fase 6 — Drive y mandos

Archivos Drive: autorización, API/DTOs, coordinador, selector de carpetas. Archivos mandos: adapters y router de entradas.

- [ ] Autorizar cuenta y scope según [04](04-SERVICIOS-COMPRAS-Y-PERMISOS.md); conectar/cambiar/desconectar y elegir carpeta.
- [ ] Reusar filtros, paginación y descarga de la API actual; aislar cuenta de los IDs locales.
- [ ] Sincronizar manualmente y al primer plano de biblioteca con exclusión de ejecuciones, sin trabajo periódico nuevo.
- [ ] Probar token vencido, 403, archivo ausente, pérdida de red y parcial; las copias siguen funcionando.
- [ ] Traducir eventos físicos a A/B/X/Y, reset, velocidad y joystick; priorizar una fuente por dispositivo.
- [ ] Probar foco, edición, repeat, desconexión y cero del joystick.

Cierre: carpetas reales con subcarpetas y cuatro formatos; mando probado físicamente y sin interferir con la escritura.

## Fase 7 — Prueba local y Play Billing

Archivos: AccessPolicy, AccessController, SecureLocalStore, PlayBillingRepository, configuración del producto y pantallas de acceso.

- [ ] Prueba explícita de siete días locales, estados/time boundary y máximo reloj observado.
- [ ] Precio desde Play; producto permanente; adquirir durante prueba y tras vencimiento.
- [ ] Manejar cancelación, pending, producto ausente, desconexión, compra ya existente y acknowledgment/reintentos.
- [ ] Restaurar en nueva instalación con la misma cuenta Play; separar caché del acceso validado.
- [ ] Excluir reseteo de acceso y relojes de pruebas del release; no incluir credenciales de servicio en el APK.
- [ ] Verificar limitaciones y textos sin suscripción/renovación/cargo final.

Cierre: compra real de prueba mediante Play, acceso mantenido al reiniciar, caso pending y restauración demostrados. No sustituir con un botón que marque premium.

## Fase 8 — Beta completa y publicación

Archivos previstos: tests unitarios/instrumentados, benchmarks, documentación de evidencias, configuración de firma y workflow Android independiente.

- [ ] Ejecutar [matriz completa](05-PRUEBAS-Y-ACEPTACION.md), dispositivos y pruebas de actualización.
- [ ] Corregir crashes, ANR, jank, pérdidas de datos y fallos de compra antes de release.
- [ ] Revisar privacidad ES/EN, permisos reales, datos declarados y materiales de Play.
- [ ] Distribuir AAB firmado en pruebas internas; después cumplir pruebas cerradas si corresponde.
- [ ] Revisar release con R8, código de diagnóstico excluido y secrets protegidos.
- [ ] Publicar con despliegue controlado y criterios de parada según [06](06-CI-Y-PUBLICACION.md).

Cierre: checklist firmado por responsable de implementación/QA, sin fallos críticos abiertos y con evidencia por requisito.
