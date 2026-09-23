import Foundation
import MetricKit
import os

/// Writes one line per MetricKit payload to the unified log (category `metrics`), so launch,
/// hang and crash data can be read on a device with Console or `log stream`.
///
/// Nothing leaves the device and nothing is kept: the summary goes to `os.Logger` only, with no
/// network call and no file. What Apple itself gathers for Xcode Organizer depends on the user's
/// analytics consent and does not pass through this type.
final class MetricKitLogger: NSObject, MXMetricManagerSubscriber, Sendable {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.vil555tim.onecart",
        category: "metrics"
    )

    /// Call once at launch; the owner keeps this instance alive for the process lifetime.
    func start() {
        MXMetricManager.shared.add(self)
    }

    /// MetricKit may call these off the main thread; the type holds nothing but its logger.
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let line = MetricPayloadSummary.line(for: MetricSnapshot(payload))
            logger.notice("\(line, privacy: .public)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let line = MetricPayloadSummary.line(for: DiagnosticSnapshot(payload))
            logger.error("\(line, privacy: .public)")
        }
    }
}

/// The values of an `MXMetricPayload` the summary reports. MetricKit payloads cannot be built
/// in a test, so the formatting works on this copy instead.
struct MetricSnapshot: Equatable {
    var begin: Date
    var end: Date
    var appVersion: String
    var foregroundSeconds: Double?
    var backgroundSeconds: Double?
    var cpuSeconds: Double?
    var peakMemoryMegabytes: Double?
    var launchCount: Int?
    var hangCount: Int?
}

/// The counts of an `MXDiagnosticPayload` the summary reports; call stacks are left out.
struct DiagnosticSnapshot: Equatable {
    struct Crash: Equatable {
        var signal: Int?
        var exceptionType: Int?
        var exceptionCode: Int?
    }

    var begin: Date
    var end: Date
    var appVersion: String?
    var crashes: [Crash]
    var hangCount: Int
    var cpuExceptionCount: Int
    var diskWriteExceptionCount: Int
    var launchDiagnosticCount: Int
}

enum MetricPayloadSummary {
    static func line(for metrics: MetricSnapshot) -> String {
        var fields = ["metrics", window(metrics.begin, metrics.end), "v\(metrics.appVersion)"]
        fields.append(contentsOf: [
            metrics.foregroundSeconds.map { "fg=\(seconds($0))" },
            metrics.backgroundSeconds.map { "bg=\(seconds($0))" },
            metrics.cpuSeconds.map { "cpu=\(seconds($0))" },
            metrics.peakMemoryMegabytes.map { "peakMem=\(Int($0.rounded()))MB" },
            metrics.launchCount.map { "launches=\($0)" },
            metrics.hangCount.map { "hangs=\($0)" },
        ].compactMap(\.self))
        return fields.joined(separator: " ")
    }

    static func line(for diagnostics: DiagnosticSnapshot) -> String {
        var fields = ["diagnostics", window(diagnostics.begin, diagnostics.end)]
        if let version = diagnostics.appVersion {
            fields.append("v\(version)")
        }
        fields.append(contentsOf: [
            "crashes=\(diagnostics.crashes.count)",
            "hangs=\(diagnostics.hangCount)",
            "cpuExceptions=\(diagnostics.cpuExceptionCount)",
            "diskWrites=\(diagnostics.diskWriteExceptionCount)",
            "launches=\(diagnostics.launchDiagnosticCount)",
        ])
        // Signal and Mach exception numbers identify the crash kind without a call stack.
        fields.append(contentsOf: diagnostics.crashes.prefix(maxCrashDetails).map(crashField))
        return fields.joined(separator: " ")
    }

    /// Keeps one log line short when a payload carries many crashes.
    static let maxCrashDetails = 3

    private static func window(_ begin: Date, _ end: Date) -> String {
        let format = Date.ISO8601FormatStyle(timeZone: .gmt)
        return "\(begin.formatted(format))/\(end.formatted(format))"
    }

    private static func seconds(_ value: Double) -> String {
        "\(Int(value.rounded()))s"
    }

    private static func crashField(_ crash: DiagnosticSnapshot.Crash) -> String {
        let parts = [
            crash.signal.map { "signal=\($0)" },
            crash.exceptionType.map { "type=\($0)" },
            crash.exceptionCode.map { "code=\($0)" },
        ].compactMap(\.self)
        return "crash(\(parts.isEmpty ? "unknown" : parts.joined(separator: ",")))"
    }
}

extension MetricSnapshot {
    init(_ payload: MXMetricPayload) {
        self.init(
            begin: payload.timeStampBegin,
            end: payload.timeStampEnd,
            appVersion: payload.latestApplicationVersion,
            foregroundSeconds: payload.applicationTimeMetrics?.cumulativeForegroundTime
                .converted(to: .seconds).value,
            backgroundSeconds: payload.applicationTimeMetrics?.cumulativeBackgroundTime
                .converted(to: .seconds).value,
            cpuSeconds: payload.cpuMetrics?.cumulativeCPUTime.converted(to: .seconds).value,
            peakMemoryMegabytes: payload.memoryMetrics?.peakMemoryUsage.converted(to: .megabytes).value,
            launchCount: payload.applicationLaunchMetrics.map(\.histogrammedTimeToFirstDraw.totalBucketCount),
            hangCount: payload.applicationResponsivenessMetrics.map(\.histogrammedApplicationHangTime.totalBucketCount)
        )
    }
}

extension DiagnosticSnapshot {
    init(_ payload: MXDiagnosticPayload) {
        let crashes = payload.crashDiagnostics ?? []
        let first: MXDiagnostic? = crashes.first
            ?? payload.hangDiagnostics?.first
            ?? payload.cpuExceptionDiagnostics?.first
            ?? payload.diskWriteExceptionDiagnostics?.first
            ?? payload.appLaunchDiagnostics?.first
        self.init(
            begin: payload.timeStampBegin,
            end: payload.timeStampEnd,
            appVersion: first?.applicationVersion,
            crashes: crashes.map {
                Crash(
                    signal: $0.signal?.intValue,
                    exceptionType: $0.exceptionType?.intValue,
                    exceptionCode: $0.exceptionCode?.intValue
                )
            },
            hangCount: payload.hangDiagnostics?.count ?? 0,
            cpuExceptionCount: payload.cpuExceptionDiagnostics?.count ?? 0,
            diskWriteExceptionCount: payload.diskWriteExceptionDiagnostics?.count ?? 0,
            launchDiagnosticCount: payload.appLaunchDiagnostics?.count ?? 0
        )
    }
}
