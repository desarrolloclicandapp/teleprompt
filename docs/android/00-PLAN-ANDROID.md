# Plan completo de implementación de Teleprompt para Android

Fecha de preparación: 13 de octubre de 2026. Referencia de código: commit `548a1d6`, versión iOS configurada `1.1.1`.

Estado: documentación de implementación; no existe todavía un proyecto Android en este repositorio. Las rutas Android que aparecen en estos documentos son propuestas, no archivos implementados. Este trabajo crea exclusivamente archivos `.md`.

## Objetivo y límites

Crear una aplicación Android nativa con las funcionalidades actuales de Teleprompt. Mantener la aplicación iOS funcionando y conservar su código, firma, compras y workflows. No introducir backend, cuentas propias, suscripciones, anuncios, OCR, sincronización bidireccional ni funcionalidades adicionales.

Recomendación técnica: Kotlin y Jetpack Compose, proyecto independiente en `android/` dentro de este repositorio. SwiftUI, StoreKit, AVFoundation y los mecanismos de documentos de Apple necesitan equivalentes Android; no se trasladan como código ejecutable. Se reutilizan especificaciones, textos, identidad visual, contratos de Drive y casos de prueba. No se propone migrar iOS a un framework multiplataforma.

## Documentos y orden de lectura

| Documento | Para qué sirve |
| --- | --- |
| [01 — Inventario y equivalencias](01-INVENTARIO-Y-PARIDAD.md) | Qué hace el código actual y qué archivo Android corresponde a cada parte. |
| [02 — Arquitectura y contratos](02-ARQUITECTURA-Y-CONTRATOS.md) | Estructura, modelos, estados, almacenamiento y ciclo de vida. |
| [03 — Fases de implementación](03-FASES-DE-IMPLEMENTACION.md) | Orden de trabajo, archivos a crear, dependencias y condiciones de cierre. |
| [04 — Servicios, compras y permisos](04-SERVICIOS-COMPRAS-Y-PERMISOS.md) | Drive, Billing, importadores, cámara, mandos y límites sin backend. |
| [05 — Pruebas y aceptación](05-PRUEBAS-Y-ACEPTACION.md) | Cómo demostrar paridad, fluidez, compras y recuperación ante errores. |
| [06 — Compilación y publicación](06-CI-Y-PUBLICACION.md) | Windows, CI, firma, Play Console, beta y lanzamiento. |

## Funcionalidades que deben llegar a Android

- Biblioteca local de guiones, búsqueda por título y contenido, orden por fecha o nombre y agrupación por origen.
- Edición de título y texto; guardado al salir y antes de abrir el lector.
- Importación múltiple de TXT, Markdown como texto, PDF con texto y DOCX.
- Vinculación de una carpeta local y descarga de archivos desde una carpeta de Google Drive, incluyendo subcarpetas.
- Lectura sin conexión; avance continuo; pausa, reanudación, inicio del guion y progreso.
- Velocidad entre 200 y 3000, distribuida en exactamente 30 niveles; memoria de velocidad, tamaño y espejos.
- Cuenta inicial de tres segundos; reanudar una lectura pausada sin una nueva cuenta.
- Panel desplazable y redimensionable en ancho y alto por separado, también en horizontal.
- Pantalla encendida mientras se usa el lector, respetando el brillo elegido por el usuario.
- Cámara frontal y grabación opcionales; pausa/reanudación de vídeo y guardado en la galería.
- Teclado, mando compatible y RemotePAD, sujetos a pruebas con el dispositivo físico.
- Acceso gratuito local durante siete días desde la activación y compra de por vida opcional antes o después de vencer.
- Restauración de compra, borrado de biblioteca/desconexión de fuentes y privacidad en español e inglés.

La lista describe paridad de comportamiento, no la incorporación de nuevas funciones. No trasladar automáticamente pantallas o mecanismos de diagnóstico que no formen parte del flujo de uso.

## Hechos que condicionan el plan

1. `StoreKitConfiguration.swift` y `PurchaseManager.swift` implementan una prueba **local**, sin producto gratuito en la tienda. El único IAP actual es `com.APP.lifetime`. El README raíz describe el modelo anterior y no debe usarse como especificación de compras.
2. `RootView.swift` sincroniza Drive al abrir la biblioteca y al volver al primer plano cuando hay carpeta elegida. También existe el botón manual. El README solo menciona sincronización manual; preservar lo que hace el código, sin crear un servicio continuo.
3. La cifra mostrada como palabras/minuto controla un desplazamiento proporcional a velocidad y tamaño de letra. No existe conteo de palabras ni calibración exacta de WPM. Android debe reproducir la sensación actual y documentar la calibración; no prometer una precisión que iOS no implementa.
4. La compra de Apple no acredita una compra en Google Play. No hay sistema propio de identidad ni unificación de licencias entre plataformas.
5. La prueba local y el caché de compra no pueden ofrecer protección absoluta frente a reinstalaciones, borrado de datos o manipulación del dispositivo sin una autoridad externa.
6. Las pruebas de StoreKit y captura de precio en GitHub han fallado anteriormente en el entorno de simulador. No copiar ese mecanismo ni declarar Android validado por tener compilación verde.

## Decisiones propuestas y pendientes

| Decisión | Propuesta | Cuándo cerrar |
| --- | --- | --- |
| Stack | Kotlin, Compose, ViewModel, coroutines/Flow, Room y DataStore. | Fase 0. |
| Compatibilidad | `minSdk 29` como propuesta inicial; `targetSdk` según requisito vigente de Play, hoy API 36. | Antes de crear el proyecto. |
| Identificador Android | `com.viraltia.teleprompt`, previa comprobación de disponibilidad/control en Play Console. | Antes de subir el primer AAB. |
| Producto de por vida | ID Android propuesto `lifetime_unlock`; confirmar reglas y disponibilidad en Play. No copiar `com.APP.lifetime`. | Fase 0 y consola. |
| Precio | Seleccionado en Play Console y mostrado desde Billing; no fijarlo a 19,99 ni convertir el precio iOS a mano. | Antes de beta con compras. |
| Biblioteca PDF | Selección mediante prueba técnica de extracción, mantenimiento, licencia, tamaño y memoria. | Fase 0. |
| Mandos | Dispositivos concretos disponibles para reproducir A/B/X/Y y joystick. | Antes de fase 6. |
| Cuenta de publicación | Comprobar si es cuenta de organización o personal y qué requisitos muestra la consola. | Fase 0. |

Estas son decisiones del plan; todavía no se ha creado un producto, reservado un identificador ni contratado un servicio.

## Secuencia general

Preparación y pruebas técnicas → proyecto/base local → biblioteca e importación → lector y rendimiento → cámara → Drive → mandos → compras → validación integral → beta de Play → publicación.

Configurar Play Console y OAuth pronto, aunque sus funcionalidades se implementen después: pueden bloquear pruebas al final. Priorizar la prueba técnica del lector, PDF, cámara y Billing antes de invertir en todas las pantallas.

Los tiempos se estimarán al cerrar la fase 0. No asignar una fecha de lanzamiento sin conocer el hardware de prueba, las verificaciones de Google y los resultados de las pruebas técnicas.

## Riesgos y cómo cerrarlos

| Riesgo | Medida prevista | Evidencia que permite cerrarlo |
| --- | --- | --- |
| Rehacer SwiftUI afecta a iOS | Proyecto Android separado; revisar alcance de cada commit. | Diff limitado a Android/docs y workflows añadidos. |
| Texto trabado con cámara o guion largo | Prueba de frame clock y separación medición/traslación antes de toda la UI. | Mediciones y lectura física en dos frecuencias. |
| PDF funciona solo en Android reciente | Evaluar extracción sobre minSdk, fixtures y licencia. | Texto esperado en matriz de versiones. |
| Cámara cambia según fabricante | CameraX, estados y pruebas físicas de pausa/rotación/guardado. | Vídeos reproducibles de al menos dos dispositivos. |
| RemotePAD tiene códigos distintos | Capturar eventos reales y resolver por comandos semánticos. | Tabla medida de botones/ejes y pruebas de repetición. |
| OAuth debug funciona y Play no | Registrar firma de instalación y scope/verificación correctos. | Drive autorizado desde build instalado por Play. |
| Compra pendiente o sin acknowledgment | Estados separados y reintentos idempotentes. | Pruebas reales de pending, compra y restauración. |
| Reinstalación reinicia prueba local | Documentar límite sin backend; separar borrado de biblioteca del acceso. | Pruebas de ambos tipos de borrado y textos correctos. |
| Revisión/publicación bloqueada | Preparar consola y verificaciones en fase 0. | Checklist de consola y beta cerrada cuando aplique. |

## Criterio de finalización del proyecto

Android estará listo cuando estén cerradas todas las fases, pase la matriz de aceptación, se pruebe una compra desde una instalación de Play, se reproduzca una grabación real y se mida la fluidez en teléfonos físicos. La versión iOS deberá permanecer separada y sin modificaciones causadas por este port.

Requisitos de Play consultados: [nivel objetivo de API](https://support.google.com/googleplay/android-developer/answer/11926878) y [pruebas para nuevas cuentas personales](https://support.google.com/googleplay/android-developer/answer/14151465). Revalidar estas condiciones antes del lanzamiento.
