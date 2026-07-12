import SwiftUI
import WidgetKit

@main
struct PulseBarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CPUWidget()
        RAMWidget()
        NetworkWidget()
        StorageWidget()
        DevServersWidget()
        TopAppsWidget()
    }
}
