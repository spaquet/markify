import AppKit
import FoundationModels

/// Foundation Models eligibility is separate from Sequoia's system Writing Tools.
enum IntelligenceAvailability: Equatable, Sendable {
    case available
    case unavailable(Reason)

    enum Reason: Sendable {
        case deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady, requiresMacOS26, unknown
    }

    @MainActor static var current: Self {
        guard #available(macOS 26, *) else {
            return .unavailable(NSWritingToolsCoordinator.isWritingToolsAvailable ? .requiresMacOS26 : .deviceNotEligible)
        }
        return modelAvailability
    }

    static func check() async -> Self {
        if #available(macOS 26, *) {
            return await Task.detached { modelAvailability }.value
        }
        return await current
    }

    @available(macOS 26, *)
    private static var modelAvailability: Self {
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled): return .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady): return .unavailable(.modelNotReady)
        @unknown default: return .unavailable(.unknown)
        }
    }
}
