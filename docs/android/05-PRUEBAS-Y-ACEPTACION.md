# Pruebas, dispositivos y aceptación

## Evidencia necesaria

Cada fila debe quedar vinculada a resultado, build/versionCode, dispositivo/API, fecha y responsable. Resultado permitido: pendiente, pasa o falla; no marcar aprobado por compilación ni por mocks. Estos documentos son un plan, no resultados de Android.

Separar pruebas unitarias de lógica, instrumentación/Compose de UI y pruebas físicas de cámara, rendimiento, mandos y Play Billing. Los mocks prueban estados, pero no prueban que Google pueda completar una compra o que un archivo grabado se reproduzca.

## Matriz funcional

| Área | Casos mínimos | Resultado requerido |
| --- | --- | --- |
| Arranque | Primera instalación, sin red, proceso recreado | Estado correcto, sin bloqueo por Drive/cámara. |
| Biblioteca | Importar, editar, borrar, buscar en contenido, ordenar y agrupar | Datos y UUID coherentes; persisten tras reinicio. |
| Editor | Cerrar, Back, abrir lector, girar y terminar proceso | Último texto guardado sin duplicar guion. |
| Importación | TXT UTF-8/BOM, MD, PDF textual, DOCX; selección múltiple | Texto utilizable, párrafos y errores por archivo. |
| Documentos adversos | Vacío, corrupto, protegido, escaneado, grande, ZIP expandido | Error visible; sin OOM/ANR ni biblioteca parcialmente destruida. |
| Carpeta local | Subcarpetas, mismo nombre, permiso revocado, archivo movido | Identidad estable y copias legibles offline. |
| Drive | Elegir/cambiar cuenta/carpeta, múltiples páginas/subcarpetas | Descarga completa y sin mezcla de cuentas. |
| Red | 401, 403, 404, 429, timeout y desconexión a mitad | Retry acotado; resumen parcial; no pérdida local. |
| Reimportación | Mismo origen y edición local seguida de sync | Sin duplicados; reemplazo igual al contrato documentado. |
| Velocidad | Nivel 1/30, todos los pasos y cambios por mando | Exactamente 30; extremos 200/3000; distancia independiente de Hz. |
| Lectura | Primer Play, cancelar cuenta, pausa, resume, Inicio y final | Countdown solo al inicio; posición/progreso acotados. |
| Ajustes | Fuente/espejos/velocidad, cerrar y reabrir app | Valores recordados, validados y sin flash de defaults. |
| Geometría | Vertical, ambos horizontales, cámara sí/no, insets | Panel y tiradores accesibles; ancho y alto independientes. |
| Gestos | Arrastrar texto, panel, cada borde y esquina | Sin scroll accidental al resize ni eje cambiado al estirar otro. |
| Pantalla | Inactividad dentro del lector y salir | Pantalla permanece activa; luego autoapagado normal; brillo preservado. |
| Cámara | Denegar/retirar permisos, no cámara frontal | Mensaje comprensible; lectura sigue usable. |
| Grabación | Inicio, varias pausas, resume, stop y salir pausado | Un vídeo correcto; audio sincronizado; no texto quemado. |
| Grabación adversa | Rotar, bloqueo, salir, llamada, poco disco y taps rápidos | Política explícita, salida recuperable y recursos liberados. |
| Mandos | A/B/X/Y, joystick, repeat, desconectar, otras fuentes | Una acción por pulsación; eje cero; no secuestrar editor. |
| Idiomas | ES/EN, fechas, precio, plural, accesibilidad | Ninguna cadena Apple ni clave sin traducir; TalkBack usable. |
| Borrar datos | Biblioteca y fuentes vinculadas | Confirmación; no reiniciar prueba ni eliminar compra/archivos externos. |
| Actualización | Instalar beta nueva sobre beta anterior | Biblioteca, fuentes y ajustes preservados; migraciones explícitas. |

## Casos de acceso y compra

### Pruebas locales automatizadas

- Sin fecha de prueba: `FreeNotStarted`; iniciar una vez y conservar fecha.
- Fin exacto a `inicio + 7 × 24 h`; un instante antes activo, en el límite vencido.
- Varios husos, horario de verano y retroceso/avance de reloj; no extender plazo retrocediendo.
- Acceso comprado domina prueba activa o vencida.
- Borrar biblioteca no borra política de acceso; reinstalación documentada como limitación.
- Inicio con tienda ausente y caché previo; consulta fallida vs consulta válida sin compra.
- Producto ausente, cancelar, pending, error, doble tap y callback repetido.
- Acknowledgment interrumpido y reconexión; procesar token una sola vez y volver a intentar lo pendiente.
- Cambio de cuenta y restauración sin compra; no desbloquear con datos de un mock en release.

### Pruebas mediante Google Play

Instalar desde pista interna/cerrada y usar license testers habilitados; revisar cuenta correcta y que el producto esté disponible. Seguir [pruebas oficiales de Billing](https://developer.android.com/google/play/billing/test).

Demostrar compra durante prueba y después de expiración con estados de test controlados; aprobación pendiente, cancelación y restauración en nueva instalación. Verificar precio de tienda y acknowledgment. Registrar qué casos se hicieron realmente con Play y cuáles se cubrieron solo de forma determinista.

Pertenecer a una pista de pruebas no convierte automáticamente la cuenta en license tester: sin esa configuración puede haber cobros reales. Para repetir el desbloqueo no consumible de prueba, gestionar reembolso/revocación en la consola. El reconocimiento de compras de license testers tiene una ventana de prueba acelerada; comprobarla en la documentación en vez de esperar los tres días de producción. La prueba gratuita de esta app sigue siendo local y no hereda aceleración de trials de suscripciones.

Los argumentos para alterar reloj/acceso deben limitarse a builds de pruebas. No distribuir reset de licencia en producción y no llamar compra exitosa a una pantalla que solo simula premium.

## Rendimiento y fluidez

La app debe conservar velocidad visual aunque cambie la frecuencia de pantalla. Probar cálculo con secuencias de deltas de 60/90/120 Hz y una pausa larga; el primer frame tras reanudar no debe sumar tiempo oculto. Medir en build release o benchmark equivalente, no solamente debug.

Escenarios: guion corto y largo, tamaño mínimo/máximo, velocidad baja/media/máxima, espejo, horizontal con panel ancho/alto, controles visibles/ocultos, Drive importando y cámara grabando con audio. Importación/Drive no deben competir por el hilo de dibujo.

Propuesta de aceptación del proyecto, no umbral oficial de Android: en sesiones de dos minutos por escenario, al menos 95% de frames cumplen el presupuesto correspondiente al refresco **efectivamente obtenido** y no hay parones perceptibles repetidos de 100 ms. Registrar p50/p95/p99 y comparar con iOS. Si el sistema reduce Hz por energía/temperatura, anotarlo; no prometer 120 fps permanentes.

Usar Macrobenchmark, trazas de frames/Perfetto y observación física. Android explica presupuestos, jank y rendering en [rendimiento gráfico](https://developer.android.com/topic/performance/issues/render). Añadir muestra con carga de cámara y teléfono caliente para detectar degradación real; un gráfico de FPS no reemplaza revisar lectura.

Objetivos adicionales del proyecto: sin ANR/OOM con documentos dentro de límites definidos; sin crecimiento de memoria después de 20 aperturas/cierres de lector/cámara; cero pérdida de vídeo exitosamente finalizado; tareas/callbacks liberados al salir.

## Dispositivos y entornos

| Grupo | Cobertura |
| --- | --- |
| Emulador API mínima propuesta | Navegación, permisos, BD, documentos y compatibilidad. |
| Emulador API objetivo/reciente | Edge-to-edge, insets, rotación, cambios de comportamiento. |
| Teléfono físico 60 Hz, gama media | Fluidez, temperatura, cámara, memoria y almacenamiento. |
| Teléfono físico 90/120 Hz | Invariancia temporal y diferencias de refresco. |
| Segundo fabricante | Cámara, proveedores de archivos y ciclo de vida distintos. |
| RemotePAD real y teclado | Eventos y modalidades efectivas del hardware. |
| Instalación firmada de Play | OAuth con firma de Play, compra, pending y restauración. |
| Entorno 16 KB si hay código nativo | Dependencias PDF/cámara/medios y carga de bibliotecas. |
| Ventana pequeña/tablet si disponible | Robustez de límites; no implica añadir una edición tablet nueva. |

## Criterios de bloqueo de publicación

Bloquean beta final/producción: cobro o acceso incorrecto, compra no reconocida, pérdida de guiones, vídeo corrupto, crashes/ANR reproducibles, permisos invasivos innecesarios, tokens expuestos, texto ilegible en horizontal, tiradores inaccesibles o fluidez fallida en teléfonos soportados.

Registrar defectos menores con reproducción y decisión explícita. No deshabilitar pruebas para hacer verde el pipeline. La captura de pantalla solo demuestra layout; la grabación y el scrolling requieren evidencia física.
