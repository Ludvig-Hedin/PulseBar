import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var viewModel: PulseBarViewModel
    @Published var storageViewModel: StorageViewModel
    let storageService: StorageService

    init() {
        let storage = StorageService()
        self.storageService = storage
        self.storageViewModel = StorageViewModel(service: storage)
        self.viewModel = PulseBarViewModel(storageService: storage)
        self.viewModel.start()
        applyAppIcon()
        observeAppearance()
    }

    // MARK: - Adaptive app icon

    /// Swaps the Dock/Finder icon when the system appearance changes.
    /// Light mode → black waveform on white; dark mode → white waveform on black.
    private func applyAppIcon() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = isDark ? "AppIconDark" : "AppIconLight"
        if let img = NSImage(named: name) {
            NSApp.applicationIconImage = img
        }
    }

    private func observeAppearance() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.applyAppIcon() }
        }
        // KVO on effectiveAppearance is the most reliable trigger for dark/light switches.
        NSApp.addObserver(AppearanceObserver.shared,
                          forKeyPath: "effectiveAppearance",
                          options: [.new],
                          context: nil)
        AppearanceObserver.shared.onChange = { [weak self] in
            Task { @MainActor [weak self] in self?.applyAppIcon() }
        }
    }
}

/// Tiny KVO helper so AppState doesn't need to be NSObject.
private final class AppearanceObserver: NSObject {
    static let shared = AppearanceObserver()
    var onChange: (() -> Void)?
    override func observeValue(forKeyPath keyPath: String?,
                                of object: Any?,
                                change: [NSKeyValueChangeKey: Any]?,
                                context: UnsafeMutableRawPointer?) {
        onChange?()
    }
}
