import SwiftUI
import Charts

/// Status-over-time charts built from the scan-history index: junk over time,
/// per-category breakdown, and disk-free trend.
struct StorageTrendsView: View {
    @EnvironmentObject private var history: ScanHistoryStore

    var body: some View {
        if history.index.count < 2 {
            insufficientData
        } else {
            VStack(alignment: .leading, spacing: 16) {
                junkTrendCard
                categoryTrendCard
                diskFreeCard
            }
        }
    }

    // MARK: - Junk over time

    private var junkTrendCard: some View {
        chartCard(title: "Junk over time",
                  subtitle: "Reclaimable junk found at each scan") {
            Chart(history.junkTrend) { point in
                AreaMark(x: .value("Date", point.date),
                         y: .value("Junk", point.bytes))
                    .foregroundStyle(.orange.opacity(0.15))
                LineMark(x: .value("Date", point.date),
                         y: .value("Junk", point.bytes))
                    .foregroundStyle(.orange)
                    .symbol(.circle)
            }
            .chartYAxis { byteAxis() }
            .frame(height: 200)
        }
    }

    // MARK: - Per-category

    private var categoryTrendCard: some View {
        let points = history.categoryTrend(top: 6)
        // Distinct categories present, in a stable display order, mapped to their tints.
        let categories = StorageCategory.displayedCategories.filter { cat in
            points.contains { $0.category == cat }
        }
        return chartCard(title: "By category",
                         subtitle: "Where the junk comes from, over time") {
            Chart(points) { point in
                AreaMark(x: .value("Date", point.date),
                         y: .value("Size", point.bytes),
                         stacking: .standard)
                    .foregroundStyle(by: .value("Category", point.category.title))
            }
            .chartForegroundStyleScale(domain: categories.map(\.title),
                                       range: categories.map(\.tint))
            .chartYAxis { byteAxis() }
            .frame(height: 220)
        }
    }

    // MARK: - Disk free

    private var diskFreeCard: some View {
        chartCard(title: "Free space",
                  subtitle: "Disk space available at each scan") {
            Chart(history.diskFreeTrend) { point in
                LineMark(x: .value("Date", point.date),
                         y: .value("Free", point.bytes))
                    .foregroundStyle(.green)
                    .interpolationMethod(.monotone)
            }
            .chartYAxis { byteAxis() }
            .frame(height: 180)
        }
    }

    // MARK: - Helpers

    private func byteAxis() -> some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine()
            AxisValueLabel {
                if let bytes = value.as(Double.self) {
                    Text(ByteFormatting.memory(UInt64(max(0, bytes))))
                }
            }
        }
    }

    private func chartCard<Content: View>(title: String, subtitle: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var insufficientData: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Run more scans to see trends")
                .font(.title3.weight(.semibold))
            Text("Trends appear once you have at least two saved scans.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
