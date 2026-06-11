import Foundation
import SwiftUI

/// Cleaning categories surfaced in the Storage tab.
///
/// Inspired by PureMac (https://github.com/momenbasel/PureMac, MIT).
/// The set is intentionally fixed at compile time so each call site can switch
/// exhaustively and the safety reviewer can audit the full surface in one place.
enum StorageCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case systemJunk
    case userCache
    case aiApps
    case mailDownloads
    case trash
    case largeFiles
    case xcodeJunk
    case brewCache
    case nodeCache
    case docker
    case purgeableSpace
    case smartScan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemJunk:     return "System Junk"
        case .userCache:      return "User Cache"
        case .aiApps:         return "AI App Caches"
        case .mailDownloads:  return "Mail Downloads"
        case .trash:          return "Trash"
        case .largeFiles:     return "Large Files"
        case .xcodeJunk:      return "Xcode"
        case .brewCache:      return "Homebrew Cache"
        case .nodeCache:      return "Node / npm / yarn / pnpm"
        case .docker:         return "Docker"
        case .purgeableSpace: return "Purgeable"
        case .smartScan:      return "Smart Scan"
        }
    }

    var subtitle: String {
        switch self {
        case .systemJunk:     return "Logs, temp files, and system caches"
        case .userCache:      return "Per-app caches under ~/Library/Caches"
        case .aiApps:         return "Ollama, LM Studio, and other AI tool caches"
        case .mailDownloads:  return "Attachments preserved by Mail.app"
        case .trash:          return "Everything currently in your Trash"
        case .largeFiles:     return "Big or old files in your home folder (reveal-only)"
        case .xcodeJunk:      return "DerivedData, Archives, simulators, device support"
        case .brewCache:      return "Downloaded bottles and casks"
        case .nodeCache:      return "Package caches for npm, yarn, and pnpm"
        case .docker:         return "Reclaimable images, containers, and volumes"
        case .purgeableSpace: return "Snapshots macOS can reclaim automatically"
        case .smartScan:      return "Scan all curated categories sequentially"
        }
    }

    var symbol: String {
        switch self {
        case .systemJunk:     return "internaldrive"
        case .userCache:      return "tray.full"
        case .aiApps:         return "brain.head.profile"
        case .mailDownloads:  return "envelope.badge"
        case .trash:          return "trash"
        case .largeFiles:     return "doc.text.magnifyingglass"
        case .xcodeJunk:      return "hammer"
        case .brewCache:      return "mug"
        case .nodeCache:      return "shippingbox"
        case .docker:         return "cube.box"
        case .purgeableSpace: return "sparkles.rectangle.stack"
        case .smartScan:      return "wand.and.stars"
        }
    }

    var tint: Color {
        switch self {
        case .systemJunk:     return .gray
        case .userCache:      return .blue
        case .aiApps:         return .purple
        case .mailDownloads:  return .indigo
        case .trash:          return .red
        case .largeFiles:     return .teal
        case .xcodeJunk:      return .brown
        case .brewCache:      return .orange
        case .nodeCache:      return .green
        case .docker:         return .cyan
        case .purgeableSpace: return .mint
        case .smartScan:      return .accentColor
        }
    }

    /// Default deletion behaviour for items in this category. Trash-first is the
    /// safer choice for anything the user might second-guess.
    var defaultDeletionMode: DeletionMode {
        switch self {
        case .trash:          return .permanent     // Already in Trash; "delete" means empty it.
        case .purgeableSpace: return .trash         // No-op category; macOS handles it.
        default:              return .trash
        }
    }

    /// Some categories require Full Disk Access to read certain subpaths.
    var requiresFullDiskAccess: Bool {
        switch self {
        case .mailDownloads, .systemJunk: return true
        default: return false
        }
    }

    /// Categories included in Smart Scan. Large Files and Docker are expensive
    /// and noisy, so they're excluded by default; the user can opt them in
    /// individually.
    var isInSmartScan: Bool {
        switch self {
        case .smartScan, .largeFiles, .docker: return false
        default: return true
        }
    }

    /// Categories surfaced in the sidebar list, in order.
    static var displayedCategories: [StorageCategory] {
        [.systemJunk, .userCache, .aiApps, .mailDownloads, .xcodeJunk,
         .brewCache, .nodeCache, .docker, .trash, .largeFiles, .purgeableSpace]
    }
}

/// How a file is removed when the user confirms a cleanup.
enum DeletionMode: String, Codable, Hashable {
    /// Move to `~/.Trash`. Reversible by the user.
    case trash
    /// Permanent `FileManager.removeItem`. Not reversible.
    case permanent
    /// Same as `.permanent` but escalates to admin via AppleScript on EACCES/EPERM.
    /// Only valid for paths on `PathAllowlist.isAdminEscalationAllowed`.
    case adminPermanent

    var title: String {
        switch self {
        case .trash:          return "Move to Trash"
        case .permanent:      return "Delete Permanently"
        case .adminPermanent: return "Delete Permanently (with admin)"
        }
    }
}
