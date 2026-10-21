# Estado de implementación Android

Inicio de implementación: 21 de octubre de 2026. Rama: `codex/android-native`.
Base iOS conservada: `660cecb`, rama de publicación `codex/fix-remote-pad-abxy`.

## Entrega inicial

Se crea `android/` como proyecto autónomo y `.github/workflows/android-validation.yml` como validación específica de Android. No se modifican Swift, XcodeGen, StoreKit, Info.plist ni el workflow de publicación Codemagic iOS.

Implementado: estructura nativa, ES/EN, biblioteca/editor Room, persistencia DataStore de ajustes, importación TXT/MD/DOCX, lector nativo con cálculo temporal, controles, panel por ejes, prueba local cifrada de siete días e integración cliente de compra permanente/restauración con Google Play Billing.

Decisiones técnicas cerradas para esta base: Kotlin/Compose; minSdk 29; targetSdk 36; AGP 8.11.1; Gradle 8.13; Kotlin 2.2.20; Compose BOM 2025.09.01; Room 2.8.2 con KSP; DataStore 1.1.7; Billing 8.0.0. Revisar nuevamente los requisitos de Billing/Play antes de publicar.

El ID de producto del código es `lifetime_unlock`. Su disponibilidad y precio dependen de configuración en Play Console; no se creó un producto ni se hizo una compra real desde este trabajo. La clave pública de licencias se inyecta por propiedad Gradle. No existe backend, suscripción ni desbloqueo simulado.

## Pendientes del plan original

- PDF y validación/licencia del extractor elegido.
- Selección de carpeta SAF, permisos persistentes y grupos por origen.
- Google Drive con autorización Android y firma de Play.
- Cámara frontal, grabación, pause/resume y salida MediaStore.
- RemotePAD físico y mapeo completo X/Y/joystick/medios.
- Paridad visual final de icono y ajustes; accesibilidad de redimensionado por TalkBack.
- Rendimiento físico a 60/90/120 Hz y con grabación simultánea.
- Firma de distribución, AAB, ficha Play, producto real, pruebas de compra y publicación.

No marcar las fases 0–8 como cerradas por tener esta base. Las compras requieren pruebas Play con cuenta license tester y los puntos físicos requieren dispositivos reales.

## Comprobaciones de esta entrega

Las comprobaciones de compilación, tests, lint y emulador se registrarán al terminar la validación local. No representan todavía pruebas físicas de fluidez ni una compra de Google Play.
