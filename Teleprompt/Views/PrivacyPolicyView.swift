import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Política de privacidad")
                    .font(.largeTitle.weight(.bold))

                Text("Última actualización: 29 de julio de 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                policySection(
                    title: "1. Responsable",
                    text: "Teleprompt es ofrecida por CLIC AND APP AGENCY SL. Para consultas relacionadas con privacidad puedes escribir a marketing@clicandapp.com."
                )

                policySection(
                    title: "2. Información que procesa Teleprompt",
                    text: "Teleprompt permite crear, importar y leer guiones. Los textos creados o importados se almacenan localmente en el dispositivo para que puedas utilizarlos sin conexión. La aplicación no mantiene un servidor propio para almacenar tus guiones."
                )

                policySection(
                    title: "3. Cámara, micrófono y Fotos",
                    text: "Si activas la grabación, Teleprompt utiliza la cámara y el micrófono para grabar el vídeo. El vídeo se guarda en la aplicación Fotos mediante los servicios del sistema de Apple. Teleprompt no sube automáticamente tus vídeos a nuestros servidores ni los utiliza para publicidad. Puedes retirar estos permisos desde Ajustes del iPhone."
                )

                policySection(
                    title: "4. Google Drive",
                    text: "La conexión con Google Drive es opcional. Si eliges utilizarla, Teleprompt abre el proceso de autorización de Google y solicita únicamente acceso de lectura a los archivos de Drive que selecciones. Los archivos se descargan al dispositivo para poder leerlos y organizarlos dentro de la aplicación. Los guiones sincronizados no se envían a servidores de CLIC AND APP AGENCY SL."
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Google y sus servicios pueden procesar información conforme a sus propias condiciones y política de privacidad.")
                        .font(.body)
                    Link(
                        "Consultar la política de privacidad de Google",
                        destination: URL(string: "https://policies.google.com/privacy")!
                    )
                    .font(.body.weight(.medium))
                }

                policySection(
                    title: "5. Tokens de autorización",
                    text: "Cuando conectas Google Drive, los tokens necesarios para mantener la autorización se almacenan en el llavero seguro del dispositivo. Teleprompt no solicita ni almacena tu contraseña de Google. Puedes desconectar la cuenta desde Configuración dentro de la aplicación."
                )

                policySection(
                    title: "6. Analítica, publicidad y seguimiento",
                    text: "Teleprompt no incluye publicidad, perfiles de usuario, analítica de terceros ni seguimiento entre aplicaciones o sitios web. No utilizamos tus guiones, vídeos o grabaciones con fines comerciales."
                )

                policySection(
                    title: "7. Eliminación y control de tus datos",
                    text: "Puedes eliminar guiones desde la biblioteca de Teleprompt, borrar vídeos desde Fotos y desconectar Google Drive desde Configuración. Al eliminar la aplicación, los datos almacenados dentro de ella se eliminan conforme al funcionamiento de iOS. Los archivos que permanezcan en Google Drive o Fotos deben eliminarse desde esos servicios."
                )

                policySection(
                    title: "8. Menores",
                    text: "Teleprompt no está dirigida específicamente a menores y no solicita deliberadamente información personal de niños."
                )

                policySection(
                    title: "9. Cambios en esta política",
                    text: "Podemos actualizar esta política cuando cambien las funciones de Teleprompt o los requisitos legales. La fecha de actualización se mostrará al principio de esta pantalla."
                )

                policySection(
                    title: "10. Contacto",
                    text: "Si tienes preguntas sobre esta política o sobre el tratamiento de tus datos, contacta con CLIC AND APP AGENCY SL en marketing@clicandapp.com."
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("Privacidad")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
