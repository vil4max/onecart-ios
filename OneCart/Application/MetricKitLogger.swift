import Foundation
import MetricKit
import os
import Synchronization

/// Writes one line per MetricKit report to the unified log (category `metrics`), so daily
/// metrics and hang and crash diagnostics can be read on a device with Console or `log stream`.
///
/// Nothing leaves the device and nothing is kept: the summary goes to `os.Logger` only, with no
/// network call and no file. What Apple itself gathers for Xcode Organizer depends on the user's
/// analytics consent and does not pass through this type.
final class MetricKitLogger: Sendable {
    private let manager = MetricManager()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.vil555tim.onecart",
        category: "metrics"
    )
    /// The two report readers; their sequences never finish, so they live until `deinit`.
    private let readers = Mutex<[Task<Void, Never>]>([])

    /// Call once at launch; the owner keeps this instance alive for the process lifetime.
    /// A second call does nothing.
    func start() {
        readers.withLock { readers in
            guard readers.isEmpty else { return }
            // The readers capture the manager and logger, not `self`, so `deinit` can still run.
            readers = [
                Task { [manager, logger] in
                    for await report in manager.metricReports {
                        let line = MetricPayloadSummary.line(for: MetricSnapshot(report))
                        logger.notice("\(line, privacy: .public)")
                    }
                },
                Task { [manager, logger] in
                    for await report in manager.diagnosticReports {
                        let line = MetricPayloadSummary.line(for: DiagnosticSnapshot(report))
                        logger.error("\(line, privacy: .public)")
                    }
                },
            ]
        }
    }

    deinit {
        readers.withLock { readers in
            readers.forEach { $0.cancel() }
        }
    }
}

/// The values of a `MetricReport` the summary reports. MetricKit reports cannot be built in a
/// test, so the formatting works on this copy instead.
struct MetricSnapshot: Equatable {
    var begin: Date
    var end: Date
    var appVersion: String?
    var foregroundSeconds: Double?
    var backgroundSeconds: Double?
    var cpuSeconds: Double?
    var peakMemoryMegabytes: Double?
    var launchCount: Int?
    var hangCount: Int?
}

/// What one `DiagnosticReport` reports; call stacks are left out.
struct DiagnosticSnapshot: Equatable {
    enum Kind: Equatable {
        case crash(signal: Int?, exceptionType: Int?, exceptionCode: UInt64?)
        case hang
        case cpuException
        case diskWriteException
        case appLaunch
        case memoryException
        /// A result kind added to MetricKit after this code was written.
        case unknown
    }

    var begin: Date
    var end: Date
    var appVersion: String
    var kind: Kind
}

enum MetricPayloadSummary {
    static func line(for metrics: MetricSnapshot) -> String {
        var fields = ["metrics", window(metrics.begin, metrics.end)]
        fields.append(contentsOf: [
            metrics.appVersion.map { "v\($0)" },
            metrics.foregroundSeconds.map { "fg=\(seconds($0))" },
            metrics.backgroundSeconds.map { "bg=\(seconds($0))" },
            metrics.cpuSeconds.map { "cpu=\(seconds($0))" },
            metrics.peakMemoryMegabytes.map { "peakMem=\(Int($0.rounded()))MB" },
            metrics.launchCount.map { "launches=\($0)" },
            metrics.hangCount.map { "hangs=\($0)" },
        ].compactMap(\.self))
        return fields.joined(separator: " ")
    }

    static func line(for diagnostic: DiagnosticSnapshot) -> String {
        [
            "diagnostics",
            window(diagnostic.begin, diagnostic.end),
            "v\(diagnostic.appVersion)",
            kindField(diagnostic.kind),
        ].joined(separator: " ")
    }

    private static func window(_ begin: Date, _ end: Date) -> String {
        let format = Date.ISO8601FormatStyle(timeZone: .gmt)
        return "\(begin.formatted(format))/\(end.formatted(format))"
    }

    private static func seconds(_ value: Double) -> String {
        "\(Int(value.rounded()))s"
    }

    private static func kindField(_ kind: DiagnosticSnapshot.Kind) -> String {
        switch kind {
        case let .crash(signal, exceptionType, exceptionCode):
            // Signal and Mach exception numbers identify the crash kind without a call stack.
            let parts = [
                signal.map { "signal=\($0)" },
                exceptionType.map { "type=\($0)" },
                exceptionCode.map { "code=\($0)" },
            ].compactMap(\.self)
            return "crash(\(parts.isEmpty ? "unknown" : parts.joined(separator: ",")))"
        case .hang: return "hang"
        case .cpuException: return "cpuException"
        case .diskWriteException: return "diskWriteException"
        case .appLaunch: return "appLaunch"
        case .memoryException: return "memoryException"
        case .unknown: return "unknown"
        }
    }
}

extension MetricSnapshot {
    init(_ report: MetricReport) {
        self.init(
            begin: report.timeRange.start,
            end: report.timeRange.end,
            appVersion: report.environment?.latestApplicationVersion
        )
        // The full-day entry aggregates the whole report period; the other entries only break
        // it down by state, so they would count the same time twice.
        let values = report.intervalEntries.isEmpty ? [] : report.intervalEntries.fullDayEntry.values
        for value in values {
            switch value {
            case let .totalForegroundTime(metric):
                foregroundSeconds = metric.value.converted(to: .seconds).value
            case let .totalBackgroundTime(metric):
                backgroundSeconds = metric.value.converted(to: .seconds).value
            case let .cpuTime(metric):
                cpuSeconds = metric.value.converted(to: .seconds).value
            case let .peakMemory(metric):
                peakMemoryMegabytes = metric.value.converted(to: .megabytes).value
            case let .timeToFirstDraw(metric):
                launchCount = metric.histogram.buckets.reduce(0) { $0 + $1.count }
            case let .hangTime(metric):
                hangCount = metric.histogram.buckets.reduce(0) { $0 + $1.count }
            default:
                break
            }
        }
    }
}

extension DiagnosticSnapshot {
    init(_ report: DiagnosticReport) {
        let kind: Kind = switch report.result {
        case let .crash(crash):
            .crash(signal: crash.signal, exceptionType: crash.exceptionType, exceptionCode: crash.exceptionCode)
        case .hang: .hang
        case .cpuException: .cpuException
        case .diskWriteException: .diskWriteException
        case .appLaunch: .appLaunch
        case .memoryException: .memoryException
        @unknown default: .unknown
        }
        self.init(
            begin: report.timeRange.start,
            end: report.timeRange.end,
            appVersion: report.environment.applicationVersion,
            kind: kind
        )
    }
}
