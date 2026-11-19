import Foundation
import Darwin
import OSLog

/// A single memory reading for the running process.
struct MemorySample: Codable, Sendable, Identifiable {
    let timestamp: Date
    /// Physical memory footprint reported by the kernel (includes compressed memory).
    let physicalFootprint: UInt64
    /// Resident set size (pages currently in RAM).
    let residentSize: UInt64
    let virtualSize: UInt64

    var id: Date { timestamp }
}

/// Lightweight process memory monitor.
///
/// Samples `task_info(TASK_VM_INFO)` every few seconds and publishes the
/// current/peak footprint to SwiftUI. One JSONL sample is appended to
/// `~/Library/Logs/myleaf/memory-YYYYMMDD.jsonl` per minute (last 7 days kept).
@Observable
@MainActor
final class MemoryMonitor {

    static let shared = MemoryMonitor()

    private(set) var currentFootprint: UInt64 = 0
    private(set) var peakFootprint: UInt64 = 0
    private(set) var residentSize: UInt64 = 0
    private(set) var virtualSize: UInt64 = 0
    private(set) var lastSampleDate: Date?
    private(set) var sampleCount = 0
    private(set) var logFileURL: URL?
    private(set) var isRunning = false
    /// Live samples for the Performance panel (30 minutes at 2 s per sample).
    private(set) var history: [MemorySample] = []

    private let sampleInterval: TimeInterval = 2
    private let logInterval: TimeInterval = 60
    private let maxLogDays = 7
    private let maxHistoryCount = 900

    private var timer: DispatchSourceTimer?
    private var nextLogDate = Date.distantPast
    private let sampleQueue = DispatchQueue(label: "com.65zlui.myleaf.memory", qos: .utility)
    private let logQueue = DispatchQueue(label: "com.65zlui.myleaf.memory.log", qos: .utility)
    private let logger = Logger(subsystem: "com.65zlui.myleaf", category: "memory")

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        prepareLogDirectory()
        loadRecentHistory()

        // Give AppKit/SwiftUI a few seconds to finish launching before the
        // first persisted sample, otherwise it records a near-empty process.
        nextLogDate = Date().addingTimeInterval(10)
        sampleNow()

        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(
            deadline: .now() + sampleInterval,
            repeating: sampleInterval,
            leeway: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in
            let sample = Self.capture()
            Task { @MainActor [weak self] in
                self?.apply(sample)
            }
        }
        timer.resume()
        self.timer = timer

        logger.info("Memory monitor started")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
        logger.info("Memory monitor stopped")
    }

    /// Takes a reading immediately (used by the Diagnostics panel and tests).
    func sampleNow() {
        apply(Self.capture())
    }

    // MARK: - Sampling

    private func apply(_ sample: MemorySample) {
        // task_info can fail transiently and return a zeroed struct; ignoring
        // those samples keeps the chart from dipping to 0.
        guard sample.physicalFootprint > 0 else { return }

        currentFootprint = sample.physicalFootprint
        peakFootprint = max(peakFootprint, sample.physicalFootprint)
        residentSize = sample.residentSize
        virtualSize = sample.virtualSize
        lastSampleDate = sample.timestamp
        sampleCount += 1

        history.append(sample)
        if history.count > maxHistoryCount {
            history.removeFirst(history.count - maxHistoryCount)
        }

        if sample.timestamp >= nextLogDate {
            nextLogDate = sample.timestamp.addingTimeInterval(logInterval)
            writeLog(sample)
        }
    }

    nonisolated private static func capture() -> MemorySample {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemorySample(
                timestamp: Date(),
                physicalFootprint: 0,
                residentSize: 0,
                virtualSize: 0
            )
        }

        return MemorySample(
            timestamp: Date(),
            physicalFootprint: UInt64(info.phys_footprint),
            residentSize: UInt64(info.resident_size),
            virtualSize: UInt64(info.virtual_size)
        )
    }

    // MARK: - Persistence

    private var logDirectory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("myleaf", isDirectory: true)
    }

    /// Seeds the chart with today's persisted samples after a relaunch.
    private func loadRecentHistory(limit: Int = 120) {
        let url = logDirectory
            .appendingPathComponent("memory-\(Self.dayFormatter.string(from: Date())).jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let samples = text
            .split(separator: "\n")
            .suffix(limit)
            .compactMap { line in
                try? decoder.decode(MemorySample.self, from: Data(line.utf8))
            }
            .filter { $0.physicalFootprint > 0 }

        if !samples.isEmpty {
            history = samples
        }
    }

    private func prepareLogDirectory() {
        let fm = FileManager.default
        try? fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        guard let files = try? fm.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let memoryLogs = files
            .filter { $0.lastPathComponent.hasPrefix("memory-") && $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in memoryLogs.dropLast(maxLogDays) {
            try? fm.removeItem(at: url)
        }
    }

    private func writeLog(_ sample: MemorySample) {
        let url = logDirectory
            .appendingPathComponent("memory-\(Self.dayFormatter.string(from: sample.timestamp)).jsonl")
        logFileURL = url

        guard var line = try? Self.encoder.encode(sample) else { return }
        line.append(0x0A)

        logQueue.async {
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }
}
