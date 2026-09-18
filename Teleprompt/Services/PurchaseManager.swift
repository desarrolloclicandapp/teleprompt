import Foundation
import StoreKit
import Combine

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var state: MonetizationState = .loading
    @Published private(set) var purchaseFlowState: PurchaseFlowState = .idle
    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var errorMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?
    private var didBootstrap = false
    private var trialStartDate: Date?
    private var storeKitProductsAvailable = false

    init() {
        transactionUpdatesTask = Task { [weak self] in
            guard let self else { return }
            await self.listenForTransactionUpdates()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var trialDaysRemaining: Int? {
        guard case .trialActive(let startDate, _) = state else { return nil }
        return TrialClock.remainingDays(startDate: startDate, now: Date())
    }

    var isLifetimeUnlocked: Bool {
        if case .lifetimeUnlocked = state { return true }
        return false
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-teleprompt.resetLocalMonetization") {
            KeychainStore.remove(StoreKitConfiguration.localFreeAccessStartKey)
            KeychainStore.remove(StoreKitConfiguration.cachedLifetimeKey)
            KeychainStore.remove(StoreKitConfiguration.cachedLegacyAccessKey)
            KeychainStore.remove(StoreKitConfiguration.lastObservedDateKey)
        }
#endif
        await loadProducts()
        await refreshState()
    }

    func refresh() async {
        if lifetimeProduct == nil {
            await loadProducts()
        }
        await refreshState()
    }

    func startTrial() async {
        guard !purchaseFlowState.isBusy else { return }
        guard case .trialNotStarted = state else {
            return
        }

        // This is intentionally not a StoreKit transaction. The seven-day
        // access period is a free, local feature; only the permanent unlock
        // is an In-App Purchase.
        errorMessage = nil
        cacheTrialStart(Date())
        await refreshState()
        purchaseFlowState = .success
    }

    func purchaseLifetime() async {
        guard !purchaseFlowState.isBusy else { return }
        guard let product = lifetimeProduct else {
            purchaseFlowState = .failed(String(localized: "purchase.price_unavailable"))
            return
        }

        errorMessage = nil
        purchaseFlowState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseFlowState = .failed(String(localized: "purchase.unverified"))
                    return
                }
                guard transaction.productID == StoreKitConfiguration.lifetimeProductID else {
                    purchaseFlowState = .failed(String(localized: "purchase.wrong_product"))
                    return
                }
                cacheLifetimeUnlock()
                await transaction.finish()
                await refreshState()
                purchaseFlowState = .success
            case .userCancelled:
                purchaseFlowState = .cancelled
            case .pending:
                purchaseFlowState = .pending
            @unknown default:
                purchaseFlowState = .failed(String(localized: "purchase.failed"))
            }
        } catch {
            purchaseFlowState = .failed(Self.purchaseErrorMessage(for: error))
        }
    }

    func restorePurchases() async {
        guard !purchaseFlowState.isBusy else { return }
        errorMessage = nil
        purchaseFlowState = .restoring
        do {
            try await AppStore.sync()
            await refreshState()
            purchaseFlowState = isLifetimeUnlocked ? .restoreSuccess : .restoreNotFound
        } catch {
            purchaseFlowState = .failed(String(localized: "purchase.restore_failed"))
        }
    }

    func clearFlowMessage() {
        if case .failed = purchaseFlowState {
            purchaseFlowState = .idle
        } else if purchaseFlowState == .restoreNotFound || purchaseFlowState == .restoreSuccess || purchaseFlowState == .pending {
            purchaseFlowState = .idle
        }
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: StoreKitConfiguration.productIDs)
            lifetimeProduct = products.first(where: { $0.id == StoreKitConfiguration.lifetimeProductID })
            storeKitProductsAvailable = lifetimeProduct != nil
            errorMessage = nil
        } catch {
            storeKitProductsAvailable = false
            lifetimeProduct = nil
            errorMessage = nil
        }
    }

    private func refreshState() async {
        var hasLifetimeEntitlement = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.appBundleID == Bundle.main.bundleIdentifier,
                  transaction.revocationDate == nil else { continue }

            switch transaction.productID {
            case StoreKitConfiguration.lifetimeProductID:
                hasLifetimeEntitlement = true
            default:
                continue
            }
        }

        if hasLifetimeEntitlement {
            cacheLifetimeUnlock()
            state = .lifetimeUnlocked
            return
        }

        if await hasVerifiedLegacyAccess() {
            state = .lifetimeUnlocked
            return
        }

        // Keep a verified cache only while StoreKit is temporarily unavailable.
        // If products loaded successfully and no current entitlement exists,
        // allow the cache to be invalidated after a refund or revocation.
        if !storeKitProductsAvailable,
           KeychainStore.get(StoreKitConfiguration.cachedLifetimeKey) == "true" {
            state = .lifetimeUnlocked
            return
        }
        KeychainStore.remove(StoreKitConfiguration.cachedLifetimeKey)

        if let cached = cachedTrialStartDate {
            trialStartDate = cached
        }

        let now = trustedNow()
        state = TrialClock.state(startDate: trialStartDate, now: now)
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result,
                  transaction.appBundleID == Bundle.main.bundleIdentifier else { continue }

            if transaction.productID == StoreKitConfiguration.lifetimeProductID {
                if transaction.revocationDate == nil {
                    cacheLifetimeUnlock()
                } else {
                    KeychainStore.remove(StoreKitConfiguration.cachedLifetimeKey)
                }
            }

            await transaction.finish()
            await refreshState()
        }
    }

    private func hasVerifiedLegacyAccess() async -> Bool {
        if KeychainStore.get(StoreKitConfiguration.cachedLegacyAccessKey) == "true" {
            return true
        }

        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result,
              transaction.environment == .production,
              transaction.bundleID == Bundle.main.bundleIdentifier,
              StoreKitConfiguration.isVersion(transaction.originalAppVersion, atMost: StoreKitConfiguration.lastFreeAppVersion) else {
            return false
        }

        KeychainStore.set("true", key: StoreKitConfiguration.cachedLegacyAccessKey)
        return true
    }

    private var cachedTrialStartDate: Date? {
        guard let value = KeychainStore.get(StoreKitConfiguration.localFreeAccessStartKey),
              let timestamp = TimeInterval(value) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func cacheTrialStart(_ date: Date) {
        trialStartDate = date
        KeychainStore.set(String(date.timeIntervalSince1970), key: StoreKitConfiguration.localFreeAccessStartKey)
    }

    private func cacheLifetimeUnlock() {
        KeychainStore.set("true", key: StoreKitConfiguration.cachedLifetimeKey)
    }

    private func trustedNow() -> Date {
        let now = Date()
        let previous = KeychainStore.get(StoreKitConfiguration.lastObservedDateKey)
            .flatMap { TimeInterval($0) }
            .map { Date(timeIntervalSince1970: $0) }
        let effective = max(now, previous ?? .distantPast)
        KeychainStore.set(String(effective.timeIntervalSince1970), key: StoreKitConfiguration.lastObservedDateKey)

#if DEBUG
        let elapsedDays = ProcessInfo.processInfo.arguments
            .firstIndex(of: "-teleprompt.trialDaysElapsed")
            .flatMap { index in
                let nextIndex = ProcessInfo.processInfo.arguments.index(after: index)
                guard nextIndex < ProcessInfo.processInfo.arguments.endIndex else { return nil }
                return Double(ProcessInfo.processInfo.arguments[nextIndex])
            } ?? 0
        return effective.addingTimeInterval(elapsedDays * 24 * 60 * 60)
#else
        return effective
#endif
    }

    private static func purchaseErrorMessage(for error: Error) -> String {
        let description = error.localizedDescription
        return description.isEmpty
            ? String(localized: "purchase.failed_try_again")
            : String(format: String(localized: "purchase.failed_with_reason_format"), description)
    }
}
