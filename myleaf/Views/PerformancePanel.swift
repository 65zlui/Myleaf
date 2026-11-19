import SwiftUI
import Charts
import AppKit

/// Settings → Performance: live memory chart + per-compile phase timings.
struct PerformancePanel: View {
    var viewModel: EditorViewModel

    @State private var memoryWindow: MemoryWindow = .fiveMinutes

    private var memory: MemoryMonitor { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                memorySection
                compilationSection
            }
            .padding(16)
        }
    }

    // MARK: - Memory

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Memory", systemImage: "memorychip")
                    .font(.headline)

                Spacer()

                Picker("Window", selection: $memoryWindow) {
                    ForEach(MemoryWindow.allCases) { window in
                        Text(window.label).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Button("Sample Now") {
                    memory.sampleNow()
                }
                .controlSize(.small)
            }

            HStack(spacing: 24) {
                metric("Current", Int64(memory.currentFootprint).formattedFileSize, color: .blue)
                metric("Peak", Int64(memory.peakFootprint).formattedFileSize, color: .orange)
                metric("Resident", Int64(memory.residentSize).formattedFileSize, color: .secondary)
                Spacer()
                if let logURL = memory.logFileURL {
                    Button("Memory Log") {
                        NSWorkspace.shared.activateFileViewerSelecting([logURL])
                    }
                    .controlSize(.small)
                }
            }

            if memorySamples.isEmpty {
                placeholder("Collecting memory samples…")
            } else {
                Chart(memorySamples) { sample in
                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("MB", megabytes(sample.physicalFootprint))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.28), .blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("MB", megabytes(sample.physicalFootprint))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartYScale(domain: memoryDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let mb = value.as(Double.self) {
                                Text("\(Int(mb)) MB")
                            }
                        }
                    }
                }
                .frame(height: 190)
            }

            Text("Physical footprint, sampled every 2 s. Hover-free chart for the last \(memoryWindow.label).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var memorySamples: [MemorySample] {
        let cutoff = Date().addingTimeInterval(-memoryWindow.seconds)
        return memory.history.filter { $0.timestamp >= cutoff }
    }

    private var memoryDomain: ClosedRange<Double> {
        let values = memorySamples.map { megabytes($0.physicalFootprint) }
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...100
        }
        let padding = max(4, (maximum - minimum) * 0.25)
        return max(0, minimum - padding)...(maximum + padding)
    }

    // MARK: - Compilation

    private var compilationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Compilation", systemImage: "hammer")
                    .font(.headline)

                Spacer()

                if let average = averageDuration {
                    Text("Avg (last 5): \(format(average))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Clear") {
                    viewModel.clearCompilationHistory()
                }
                .controlSize(.small)
                .disabled(viewModel.compilationHistory.isEmpty)
            }

            if let last = viewModel.compilationHistory.last {
                HStack(spacing: 24) {
                    metric("Last", format(last.duration), color: last.success ? .blue : .red)
                    metric("Engine", format(last.engine), color: .secondary)
                    metric("PDF", last.pdfBytes > 0 ? Int64(last.pdfBytes).formattedFileSize : "—", color: .secondary)
                }
            }

            if viewModel.compilationHistory.isEmpty {
                placeholder("Press ⌘B to compile; per-build timings will appear here.")
            } else {
                Chart(phaseBars) { bar in
                    BarMark(
                        x: .value("Time", bar.date),
                        y: .value("Seconds", bar.seconds)
                    )
                    .foregroundStyle(by: .value("Phase", bar.phase))
                    .opacity(bar.success ? 1 : 0.45)
                    .cornerRadius(2)
                }
                .chartForegroundStyleScale([
                    "Preparation": Color.gray,
                    "Engine": Color.blue,
                    "PDF cache": Color.teal,
                ])
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(String(format: "%.2fs", seconds))
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 190)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(viewModel.compilationHistory.suffix(6).reversed())) { record in
                        HStack(spacing: 8) {
                            Image(systemName: record.success
                                  ? "checkmark.circle.fill"
                                  : "xmark.octagon.fill")
                                .foregroundStyle(record.success ? .green : .red)
                                .font(.caption)

                            Text(record.date, format: .dateTime.hour().minute().second())
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(record.engineVersion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer()

                            Text(format(record.duration))
                                .font(.caption.monospacedDigit())

                            if record.pdfBytes > 0 {
                                Text(Int64(record.pdfBytes).formattedFileSize)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private struct PhaseBar: Identifiable {
        let id = UUID()
        let date: Date
        let phase: String
        let seconds: Double
        let success: Bool
    }

    private var phaseBars: [PhaseBar] {
        viewModel.compilationHistory.suffix(10).flatMap { record in
            [
                PhaseBar(date: record.date, phase: "Preparation", seconds: record.preparation, success: record.success),
                PhaseBar(date: record.date, phase: "Engine", seconds: record.engine, success: record.success),
                PhaseBar(date: record.date, phase: "PDF cache", seconds: record.pdfCache, success: record.success),
            ].filter { $0.seconds > 0 }
        }
    }

    private var averageDuration: TimeInterval? {
        let durations = viewModel.compilationHistory.suffix(5).filter(\.success).map(\.duration)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    // MARK: - Helpers

    private func metric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func megabytes(_ bytes: UInt64) -> Double {
        Double(bytes) / 1_048_576
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3fs", seconds)
    }
}

private enum MemoryWindow: String, CaseIterable, Identifiable {
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneMinute: return "1m"
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        case .thirtyMinutes: return "30m"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1800
        }
    }
}
