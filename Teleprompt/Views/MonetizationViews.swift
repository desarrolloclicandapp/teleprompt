import SwiftUI

struct MonetizationGateView<Content: View>: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.scenePhase) private var scenePhase
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Group {
            switch purchaseManager.state {
            case .loading:
                MonetizationLoadingView()
            case .trialNotStarted:
                TrialIntroductionView()
            case .trialActive(_, _), .lifetimeUnlocked:
                content()
            case .trialExpired:
                LifetimePaywallView()
            }
        }
        .task {
            await purchaseManager.bootstrapIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await purchaseManager.refresh() }
        }
    }
}

private struct MonetizationLoadingView: View {
    var body: some View {
        MonetizationSurface {
            ProgressView()
                .controlSize(.large)
            Text("Comprobando tu acceso…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

struct TrialIntroductionView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        MonetizationSurface {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(.mint)

            Text(String(localized: "trial.access_title"))
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(String(localized: "trial.access_description"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let product = purchaseManager.lifetimeProduct {
                VStack(spacing: 4) {
                    Text(String(localized: "trial.lifetime_unlock"))
                        .font(.headline)
                    Text(product.displayPrice)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .accessibilityIdentifier("trial.lifetime_price")
                    Text(String(localized: "trial.one_time_purchase_terms"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.mint)
                .multilineTextAlignment(.center)
            }

            MonetizationBullet(text: "trial.bullet.one_time_purchase")
            MonetizationBullet(text: "trial.bullet.no_automatic_renewal")
            MonetizationBullet(text: "trial.bullet.no_charge_after_access")

            Button(String(localized: "trial.start_access")) {
                Task { await purchaseManager.startTrial() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(purchaseManager.trialProduct == nil || purchaseManager.purchaseFlowState.blocksPurchase)

            RestorePurchaseButton()
            if let errorMessage = purchaseManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            PurchaseFlowFeedback(manager: purchaseManager)
        }
        .accessibilityIdentifier("trial.introduction")
    }
}

struct LifetimePaywallView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        MonetizationSurface {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 48))
                .foregroundStyle(.mint)

            Text("Tu prueba gratuita ha terminado")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("Desbloquea la aplicación para siempre con un único pago.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Pago único · Sin suscripción")
                .font(.headline)
                .foregroundStyle(.mint)

            Button {
                Task { await purchaseManager.purchaseLifetime() }
            } label: {
                HStack {
                    Text("Desbloquear de por vida")
                    Spacer()
                    if let product = purchaseManager.lifetimeProduct {
                        Text(product.displayPrice)
                    } else {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(purchaseManager.lifetimeProduct == nil || purchaseManager.purchaseFlowState.blocksPurchase)

            RestorePurchaseButton()
            if let errorMessage = purchaseManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            PurchaseFlowFeedback(manager: purchaseManager)
        }
    }
}

private struct RestorePurchaseButton: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        Button("Restaurar compra") {
            Task { await purchaseManager.restorePurchases() }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(purchaseManager.purchaseFlowState.blocksPurchase)
    }
}

private struct PurchaseFlowFeedback: View {
    @ObservedObject var manager: PurchaseManager

    var body: some View {
        Group {
            if case .pending = manager.purchaseFlowState {
                Text("La compra está pendiente de confirmación. El acceso se activará cuando Apple la apruebe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if manager.purchaseFlowState.isBusy {
                ProgressView("Procesando…")
                    .font(.caption)
            } else if case .failed(let message) = manager.purchaseFlowState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else if case .restoreNotFound = manager.purchaseFlowState {
                Text("No se encontró una compra lifetime para esta cuenta de Apple.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct MonetizationBullet: View {
    let text: LocalizedStringKey

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)
    }
}

private struct MonetizationSurface<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18, content: content)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 48)
                    .frame(maxWidth: .infinity, minHeight: 600)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MonetizationStatusSection: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        Section("Acceso a Teleprompt") {
            switch purchaseManager.state {
            case .trialActive(_, _):
                Label(
                    String(format: String(localized: "trial.days_remaining_format"), purchaseManager.trialDaysRemaining ?? 0),
                    systemImage: "clock"
                )
            case .lifetimeUnlocked:
                Label("Acceso de por vida", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.mint)
            default:
                EmptyView()
            }

            if !purchaseManager.isLifetimeUnlocked {
                Button {
                    Task { await purchaseManager.purchaseLifetime() }
                } label: {
                    HStack {
                        Text("Adquirir acceso de por vida")
                        Spacer()
                        if let product = purchaseManager.lifetimeProduct {
                            Text(product.displayPrice)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
                }
                .disabled(purchaseManager.lifetimeProduct == nil || purchaseManager.purchaseFlowState.blocksPurchase)

                Button {
                    Task { await purchaseManager.restorePurchases() }
                } label: {
                    HStack {
                        Text("Restaurar compra")
                        Spacer()
                        if purchaseManager.purchaseFlowState.isBusy {
                            ProgressView()
                        }
                    }
                }
                .disabled(purchaseManager.purchaseFlowState.blocksPurchase)
            }

            if case .restoreNotFound = purchaseManager.purchaseFlowState {
                Text("No se encontró una compra lifetime para esta cuenta de Apple.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .failed(let message) = purchaseManager.purchaseFlowState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
