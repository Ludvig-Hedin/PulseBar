import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var viewModel: PulseBarViewModel

    init() {
        self.viewModel = PulseBarViewModel()
        self.viewModel.start()
    }
}
