# Teleprompt Android — primera base nativa

Proyecto independiente Kotlin/Jetpack Compose, `minSdk 29`, `targetSdk 36`.
El código iOS, XcodeGen, firma y Codemagic iOS no se modifican.

## Incluido en esta entrega

- Biblioteca local Room, creación, búsqueda, orden, edición y borrado.
- Importación de TXT, Markdown y DOCX con tamaño acotado. PDF todavía pendiente.
- Lector nativo con Choreographer, cálculo por tiempo real y layout de texto cacheado.
- 30 niveles de 200 a 3000, cuenta inicial, pausa/reanudación inmediata e Inicio.
- Espejos, memoria de ajustes y panel movible/redimensionable por eje en ambas orientaciones.
- Pantalla encendida en el lector y liberación al salir.
- Teclas básicas/DPAD para lectura; no se declara todavía compatibilidad RemotePAD completa.
- Prueba local explícita de siete días, registro privado cifrado y compra única mediante Play Billing.
- Recursos en español e inglés y workflow Android independiente de validación.

## Todavía no está listo para publicar

Faltan cámara/grabación, Drive, carpetas locales persistentes, PDF, mapeo completo del mando y pruebas físicas de rendimiento. El producto y la firma/OAuth de Google Play no se crean desde el código. No hay backend ni transferencia de compras Apple → Google.

Esta es una entrega inicial del plan, no una afirmación de paridad completa ni un release de tienda. El gate permite probar el lector durante siete días; no incluye un botón para saltarse pagos ni un reset de acceso.

## Compilar en Windows

Requisitos fijados: Gradle 8.13 (wrapper), AGP 8.11.1, Kotlin/Compose compiler 2.2.20, JDK 17 o compatible, Android SDK 36 y Build Tools 35.0.0. Android Studio incluye las herramientas necesarias.

Establecer `JAVA_HOME` y `ANDROID_HOME` en el entorno local o configurar el SDK en `local.properties` (ignorado). Desde esta carpeta:

```powershell
.\gradlew.bat testDebugUnitTest lintDebug assembleDebug assembleRelease
```

APK de pruebas: `app/build/outputs/apk/debug/app-debug.apk`.
El APK release se compila sin configurar una firma de distribución y no se debe subir a Play como release listo.
Los tests de dispositivo se ejecutan con `connectedDebugAndroidTest` sobre un emulador aislado.

## Activar las compras de Google Play

1. Confirmar el applicationId `com.viraltia.teleprompt` en la cuenta Play correspondiente.
2. Crear un producto de pago único con ID `lifetime_unlock`, opción de compra permanente y precio/localizaciones. No crear suscripción ni producto de prueba gratuita.
3. Obtener la clave pública RSA de licencias/compras de esa app en Play Console. Es una clave pública, no una cuenta de servicio ni un secreto privado.
4. Compilar con la propiedad Gradle `playBillingPublicKey` (por ejemplo, `ORG_GRADLE_PROJECT_playBillingPublicKey` en el entorno CI). El valor por defecto vacío impide conceder una compra sin verificarla.
5. Configurar firma propia, pista de pruebas y license testers. Probar compra, cancelación, pending, reconocimiento y restauración con Play.

No pedir ni incluir un JSON de cuenta de servicio en el APK. No hardcodear precio: se obtiene del producto de Play. Una instalación local sin producto/configuración de consola no demuestra que las compras funcionen en producción.

El cliente comprueba producto, package, estado `PURCHASED` y firma. Reconoce compras no consumibles y reintenta la reconciliación al volver al primer plano o pulsar Restaurar. Una compra `PENDING` no concede acceso. El caché de un recibo previamente verificado permite continuidad offline; una consulta exitosa sin compra lo invalida. Esto no equivale a verificación de tokens en backend y no detecta reembolsos instantáneamente sin conexión.

La prueba dura `7 × 24 h` desde el botón de activación, no desde la instalación. El borrado interno de guiones no borra el registro de acceso. Borrar almacenamiento desde Ajustes de Android o reinstalar puede reiniciar la prueba; sin backend no se promete una prueba irrepetible. Se excluyen los datos del backup automático para evitar restaurar credenciales/estado de licencia como si fueran válidos en otro dispositivo.

## Validación

Ver pruebas unitarias en `app/src/test` y smoke de dispositivo en `app/src/androidTest`.
El smoke activa una prueba local real y no otorga acceso de pago. No ejecutarlo sobre un dispositivo con datos que quieras conservar; usar un emulador dedicado.

Estado y pruebas de esta entrega: [registro de implementación](../docs/android/07-ESTADO-DE-IMPLEMENTACION.md).
