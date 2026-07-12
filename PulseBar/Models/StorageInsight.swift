import Foundation
import SwiftUI

/// A plain-language, prioritized observation about the user's storage — the
/// "smart" layer that turns raw scan numbers into something a non-expert can act
/// on. Generated deterministically by `StorageInsightsEngine` (offline, no LLM).
struct StorageInsight: Identifiable, Hashable {
    enum Kind: String {
        case reclaimable   // safe junk to clean
        case bigFootprint  // large but user-owned (large files, dev artifacts)
        case repeatOffender
        case trend
        case diskPressure
        case allClear
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    /// Bytes this insight is "about", for sorting by impact. 0 if not size-based.
    let sizeBytes: UInt64
    /// Short call-to-action, e.g. "Run Quick Clean" or "Open Disk Map".
    let actionHint: String?

    var symbol: String {
        switch kind {
        case .reclaimable:    return "sparkles"
        case .bigFootprint:   return "shippingbox"
        case .repeatOffender: return "arrow.triangle.2.circlepath"
        case .trend:          return "chart.line.uptrend.xyaxis"
        case .diskPressure:   return "exclamationmark.triangle.fill"
        case .allClear:       return "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch kind {
        case .reclaimable:    return .green
        case .bigFootprint:   return .pink
        case .repeatOffender: return .orange
        case .trend:          return .blue
        case .diskPressure:   return .red
        case .allClear:       return .secondary
        }
    }
}
