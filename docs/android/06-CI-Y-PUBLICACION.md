# Compilación, CI, beta y publicación Android

## Qué crear y qué tocar

| Ubicación | Acción prevista en la implementación |
| --- | --- |
| `android/` | Crear proyecto completo con wrapper Gradle, módulo app y catálogo de versiones. |
| `.github/workflows/android-validation.yml` | Crear workflow específico; filtrar cambios Android sin sustituir el workflow iOS. |
| `codemagic.yaml` | Añadir workflow Android independiente cuando llegue esa fase; conservar iOS y sus grupos de firma. |
| `.gitignore` | Añadir `android/.gradle`, builds, `local.properties`, keystores y secretos de servicio Android. |
| Documentación Android | Registrar versiones fijadas, comandos, matriz de dispositivos y evidencias. |
| `Teleprompt/`, `TelepromptTests/`, `TelepromptUITests/`, `project.yml` | No requieren cambios por el port. |
| Play Console y Google Cloud | Configuración externa: app, producto, firmas, OAuth, pruebas y publicación. |

Esta entrega no modifica ninguno de esos archivos operativos: solo deja el plan.

## Desarrollo local en Windows

Instalar Android Studio/SDK, emulador si el equipo lo permite y JDK compatible con AGP/Gradle elegidos. Utilizar wrapper del proyecto; no depender de un Gradle global. Las rutas del SDK se guardan en `local.properties`, excluido de Git.

Verificaciones previstas desde `android/`:

```text
.\gradlew.bat testDebugUnitTest
.\gradlew.bat lintDebug
.\gradlew.bat assembleDebug
.\gradlew.bat connectedDebugAndroidTest
.\gradlew.bat bundleRelease
```

Los comandos no son ejecutables todavía porque el proyecto Android no existe. Instrumentación requiere un dispositivo/emulador conectado. Preferir teléfono real para cámara/mandos/fluidez. La publicación Android no necesita Mac.

## Versionado y dependencias

Elegir `versionName` Android inicial como decisión de lanzamiento; no asumir que debe heredar `1.1.1` de Apple. `versionCode` entero creciente propio por cada AAB, coordinado entre workflows; no reutilizar el contador Apple ni fechas Unix por comodidad.

Fijar matriz Kotlin/Compose/AGP/Gradle/JDK y SDKs estables compatibles. Revalidar requisitos de Play y Billing antes de firmar. Según [requisitos actuales de API de Play](https://support.google.com/googleplay/android-developer/answer/11926878), nuevas apps/actualizaciones deben apuntar a API 36 desde el 31 de agosto de 2026; minSdk es una decisión distinta.

Verificar las dependencias nativas y soporte de [páginas de 16 KB](https://developer.android.com/guide/practices/page-sizes); no darlo por cubierto solo porque la aplicación esté escrita en Kotlin. Repetir revisión si se incorpora un extractor PDF con `.so`.

## Workflow de validación

1. Checkout del commit y configuración reproducible del JDK/SDK.
2. Dependencias fijadas y caché de Gradle sin secretos.
3. Tests unitarios de lógica, lint y compilación debug/release sin subir a tiendas.
4. Instrumentación/UI en emulador con API definida y tiempo de arranque acotado.
5. Publicar resultados y logs filtrados; preservar evidencia de fallos de UI cuando aporte diagnóstico.
6. Benchmark de lector en entorno controlado; complementar con hardware físico de la matriz.

No convertir pruebas locales de Billing en una llamada real a Play dentro de cada PR. Tests instrumentados de tienda se ejecutan sobre build preparado y cuenta license tester. Las credenciales de publicación no deben estar disponibles para PRs no confiables.

## Workflow de distribución Codemagic

La [guía de Android nativo de Codemagic](https://docs.codemagic.io/yaml-quick-start/building-a-native-android-app/) cubre preparación, build, artefactos y firma. Durante implementación, agregar workflow que trabaje en `android/` y use su propio grupo de variables.

Pasos previstos: preparación → checks → asignación de versionCode → bundleRelease → validación del AAB → upload a pista interna. Guardar AAB, mapping de R8 y resultados de pruebas. Activar publicación únicamente para rama/tag de release definido, con cuenta de servicio autorizada.

Primera subida manual o mediante CI según estado de Play Console. No hacer rollout a producción por cada push. Conservar el commit exacto y revisar el AAB final con R8: parsers/DTOs/SDKs pueden funcionar en debug y fallar minificados.

## Firma, OAuth y secretos

- Play App Signing administra la firma de instalación; proteger la upload key propia y su recuperación.
- Keystore, passwords y JSON de cuenta de servicio se guardan en el gestor de secretos de CI, nunca en repositorio/APK/logs.
- La cuenta de servicio solo sube versiones; no da al cliente Android un backend de verificación de compras.
- Configurar OAuth para las firmas realmente usadas al instalar desde Play. Una autorización que funciona en debug no acredita que funcione en la beta.
- Probar release instalado sobre release anterior con la misma identidad/firma; no borrar datos para ocultar fallos de migración.
- Excluir diagnósticos, reset de acceso y relojes de prueba en la variante entregada.

## Preparación Play Console

- [ ] Confirmar titular/tipo/verificación de cuenta y disponibilidad del applicationId.
- [ ] Crear aplicación, países, ficha ES/EN, icono adaptativo, gráficos y capturas reales Android.
- [ ] Activar Play App Signing y validar certificado para OAuth.
- [ ] Crear compra permanente, localizaciones, precio/países y estado disponible para pruebas.
- [ ] Configurar license testers y acceso a pista interna; comprobar que el tester instala desde esa pista.
- [ ] Completar clasificación de contenido, declaraciones de anuncios, acceso a la app y público objetivo según producto real.
- [ ] Publicar política de privacidad accesible y adaptar textos a Drive, Play, cámara, micrófono, medios y almacenamiento local.
- [ ] Revisar Data safety a partir del comportamiento real y todos los SDKs. Que no haya backend propio no implica automáticamente ausencia de datos enviados a Google.
- [ ] Probar cuenta/consentimiento de Drive disponible para quien revisa; lector utilizable sin Drive.
- [ ] Documentar prueba local sin producto gratuito ni renovación y compra única/restauración.

Para cuentas personales creadas después del 13 de noviembre de 2023, la documentación indica pruebas cerradas con al menos 12 participantes durante 14 días continuos antes de solicitar producción. No asumir que esto se aplica a una cuenta de organización: comprobar el estado concreto de la consola. Referencia: [requisitos de pruebas](https://support.google.com/googleplay/android-developer/answer/14151465).

## Notas de revisión que habrá que preparar

Explicar cómo activar los siete días locales, dónde adquirir antes del vencimiento, cómo restaurar y qué exige autorización opcional. Indicar que no existe usuario/contraseña propio, si se mantiene el alcance de este plan. No inventar cuenta demo obligatoria.

Si una revisión solicita evidencia, proporcionar un vídeo de dispositivo Android que muestre flujo y compra de prueba de Play real. No reutilizar vídeo iPhone ni capturas generadas como prueba de una compra completada.

## Lanzamiento y seguimiento

Primero pista interna, después cerrada si corresponde, luego producción controlada cuando se cumpla [05](05-PRUEBAS-Y-ACEPTACION.md). Confirmar en consola qué opciones permite el primer lanzamiento; usar rollout gradual donde esté disponible.

Vigilar Android vitals/pre-launch report y feedback de testers para crashes, ANR, vídeo, acceso y dispositivos. No agregar analítica de terceros como paso implícito. Relacionar cada reporte con build, fabricante/API y pasos concretos.

Ante pérdida de datos, fallo de compra o grabación corrupta: detener distribución y preparar corrección con versionCode mayor. No asumir que se puede reinstalar una versión antigua sobre otra nueva; preservar datos y probar migración. Mantener completamente separado el canal iOS.

## Checklist final de salida

- [ ] Todas las fases y decisiones necesarias están cerradas.
- [ ] Biblioteca y ajustes sobreviven reinicios/actualizaciones; borrado de datos respeta límites.
- [ ] Importación de los cuatro formatos y Drive con OAuth firmado de Play funcionan.
- [ ] Lector fluido en teléfonos físicos; ancho/alto independientes en horizontal.
- [ ] Vídeo con audio reproducible y RemotePAD probado físicamente.
- [ ] Compra, pending, acknowledgment y restauración verificados en Play.
- [ ] Release sin controles de reseteo de acceso, precios hardcoded ni credenciales.
- [ ] AAB válido, firmas correctas, versionCode nuevo y recursos ES/EN completos.
- [ ] Play Console/privacidad/permisos corresponden al producto entregado.
- [ ] Evidencias de QA disponibles; no quedan bloqueos de publicación.
