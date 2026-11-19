import Foundation

/// One compile run, used by the Performance panel.
struct CompilationRecord: Identifiable {
    let id = UUID()
    let date: Date
    let duration: TimeInterval
    let preparation: TimeInterval
    let engine: TimeInterval
    let pdfCache: TimeInterval
    let success: Bool
    let engineVersion: String
    let pdfBytes: Int
}
