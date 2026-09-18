import Foundation

enum StoreKitConfiguration {
    // The free access period is local to the device; it is not an In-App
    // Purchase. The permanent unlock is the only App Store product.
    static let lifetimeProductID = "com.APP.lifetime"
    static let productIDs = [lifetimeProductID]

    static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

    // AppTransaction.originalAppVersion is the marketing version, not the
    // Codemagic build number. Keep this aligned with the last version that was
    // free in App Store Connect before monetization was introduced.
    static let lastFreeAppVersion = "1.0.1"

    // This intentionally differs from the key used by the former trial IAP.
    // Existing testers receive the new local access flow once after upgrading.
    static let localFreeAccessStartKey = "teleprompt.monetization.free-access-start"
    static let cachedLifetimeKey = "teleprompt.monetization.lifetime-unlocked"
    static let cachedLegacyAccessKey = "teleprompt.monetization.legacy-access"
    static let lastObservedDateKey = "teleprompt.monetization.last-observed-date"

    static func isVersion(_ candidate: String, atMost cutoff: String) -> Bool {
        let candidateParts = versionParts(candidate)
        let cutoffParts = versionParts(cutoff)
        guard !candidateParts.isEmpty, !cutoffParts.isEmpty else { return false }

        let count = max(candidateParts.count, cutoffParts.count)
        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let cutoffPart = index < cutoffParts.count ? cutoffParts[index] : 0
            if candidatePart != cutoffPart {
                return candidatePart < cutoffPart
            }
        }
        return true
    }

    private static func versionParts(_ value: String) -> [Int] {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return [] }

        let parts = components.map { Int($0) }
        guard parts.allSatisfy({ part in
            guard let part else { return false }
            return part >= 0
        }) else {
            return []
        }

        return parts.compactMap { $0 }
    }
}

enum MonetizationState: Equatable {
    case loading
    case trialNotStarted
    case trialActive(startDate: Date, endDate: Date)
    case trialExpired
    case lifetimeUnlocked
}

enum PurchaseFlowState: Equatable {
    case idle
    case purchasing
    case restoring
    case success
    case cancelled
    case pending
    case failed(String)
    case restoreSuccess
    case restoreNotFound

    var isBusy: Bool {
        switch self {
        case .purchasing, .restoring: return true
        default: return false
        }
    }

    var blocksPurchase: Bool {
        isBusy || self == .pending
    }
}

enum TrialClock {
    static func endDate(for startDate: Date) -> Date {
        startDate.addingTimeInterval(StoreKitConfiguration.trialDuration)
    }

    static func state(startDate: Date?, now: Date) -> MonetizationState {
        guard let startDate else { return .trialNotStarted }
        let endDate = endDate(for: startDate)
        return now < endDate
            ? .trialActive(startDate: startDate, endDate: endDate)
            : .trialExpired
    }

    static func remainingDays(startDate: Date, now: Date) -> Int {
        let seconds = endDate(for: startDate).timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return max(1, Int(ceil(seconds / (24 * 60 * 60))))
    }
}
