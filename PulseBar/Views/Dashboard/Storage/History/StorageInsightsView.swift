import SwiftUI

/// Root of the "History & Trends" tab. A browse-and-analyze surface (distinct
/// from the action-oriented Storage tab) with three sections: trends, saved
/// scans, and repeat-offender folders.
struct StorageInsightsView: View {
    @EnvironmentObject private var storageVM: StorageViewModel
    @EnvironmentObject private var history: ScanHistoryStore

    enum Section: String, CaseIterable, Identifiable {
        case trends = "Trends"
        case scans = "Saved Scans"
        case offenders = "Repeat Offenders"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .trends:    return "chart.xyaxis.line"
            case .scans:     return "clock.arrow.circlepath"
            case .offenders: return "arrow.triangle.2.circlepath"
            }
        }
    }

    @State private var section: Section = .trends

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if history.index.isEmpty {
                emptyState
            } else {
                picker
                switch section {
                case .trends:    StorageTrendsView().environmentObject(history)
                case .scans:     ScanHistoryListView().environmentObject(history)
                case .offenders: RepeatOffendersView().environmentObject(history).environmentObject(storageVM)
                }
            }
        }
    }

    private var picker: some View {
        Picker("Section", selection: $section) {
            ForEach(Section.allCases) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 600)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No scan history yet")
                .font(.title3.weight(.semibold))
            Text("Run a Quick or Deep Scan a few times. PulseBar saves each one so you can watch your junk change over time and spot folders that keep filling up.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
