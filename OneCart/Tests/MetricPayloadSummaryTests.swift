import Foundation
@testable import OneCart
import Testing

/// The one-line MetricKit summaries `MetricKitLogger` writes to the unified log.
@Suite("MetricPayloadSummaryTests")
struct MetricPayloadSummaryTests {
    private static let begin = Date(timeIntervalSince1970: 1_790_000_000)
    private static let end = begin.addingTimeInterval(86400)
    private static let window = "2026-09-21T14:13:20Z/2026-09-22T14:13:20Z"

    @Test("a metric report states its window, version, times, memory, launches and hangs")
    func fullMetricLine() {
        let snapshot = MetricSnapshot(
            begin: Self.begin,
            end: Self.end,
            appVersion: "1.7.0",
            foregroundSeconds: 1234.4,
            backgroundSeconds: 56.6,
            cpuSeconds: 12.5,
            peakMemoryMegabytes: 84.7,
            launchCount: 4,
            hangCount: 1
        )

        #expect(
            MetricPayloadSummary.line(for: snapshot)
                == "metrics \(Self.window) v1.7.0 fg=1234s bg=57s cpu=13s peakMem=85MB launches=4 hangs=1"
        )
    }

    @Test("a metric the report lacks is left out rather than reported as zero")
    func missingMetricsAreOmitted() {
        let snapshot = MetricSnapshot(begin: Self.begin, end: Self.end, appVersion: "1.7.0", launchCount: 0)

        #expect(MetricPayloadSummary.line(for: snapshot) == "metrics \(Self.window) v1.7.0 launches=0")
    }

    @Test("a metric report without an environment leaves the version out")
    func missingVersionIsOmitted() {
        let snapshot = MetricSnapshot(begin: Self.begin, end: Self.end, appVersion: nil, hangCount: 2)

        #expect(MetricPayloadSummary.line(for: snapshot) == "metrics \(Self.window) hangs=2")
    }

    @Test("a crash report is identified by signal, exception type and code, without a call stack")
    func crashLine() {
        let snapshot = DiagnosticSnapshot(
            begin: Self.begin,
            end: Self.end,
            appVersion: "1.7.0",
            kind: .crash(signal: 11, exceptionType: 1, exceptionCode: 2)
        )

        #expect(
            MetricPayloadSummary.line(for: snapshot)
                == "diagnostics \(Self.window) v1.7.0 crash(signal=11,type=1,code=2)"
        )
    }

    @Test("a crash report without signal or exception details is still logged as a crash")
    func crashWithoutDetails() {
        let snapshot = DiagnosticSnapshot(
            begin: Self.begin,
            end: Self.end,
            appVersion: "1.7.0",
            kind: .crash(signal: nil, exceptionType: nil, exceptionCode: nil)
        )

        #expect(MetricPayloadSummary.line(for: snapshot) == "diagnostics \(Self.window) v1.7.0 crash(unknown)")
    }

    @Test(
        "every other diagnostic report is named by its kind",
        arguments: zip(
            [
                DiagnosticSnapshot.Kind.hang, .cpuException, .diskWriteException, .appLaunch, .memoryException,
                .unknown,
            ],
            ["hang", "cpuException", "diskWriteException", "appLaunch", "memoryException", "unknown"]
        )
    )
    func diagnosticKindLine(kind: DiagnosticSnapshot.Kind, name: String) {
        let snapshot = DiagnosticSnapshot(begin: Self.begin, end: Self.end, appVersion: "1.7.0", kind: kind)

        #expect(MetricPayloadSummary.line(for: snapshot) == "diagnostics \(Self.window) v1.7.0 \(name)")
    }
}
