import Foundation
@testable import OneCart
import Testing

/// The one-line MetricKit summaries `MetricKitLogger` writes to the unified log.
@Suite("MetricPayloadSummaryTests")
struct MetricPayloadSummaryTests {
    private static let begin = Date(timeIntervalSince1970: 1_790_000_000)
    private static let end = begin.addingTimeInterval(86400)
    private static let window = "2026-09-21T14:13:20Z/2026-09-22T14:13:20Z"

    @Test("a metric payload reports its window, version, times, memory, launches and hangs")
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

    @Test("a metric the payload lacks is left out rather than reported as zero")
    func missingMetricsAreOmitted() {
        let snapshot = MetricSnapshot(begin: Self.begin, end: Self.end, appVersion: "1.7.0", launchCount: 0)

        #expect(MetricPayloadSummary.line(for: snapshot) == "metrics \(Self.window) v1.7.0 launches=0")
    }

    @Test("a diagnostic payload counts each kind and names at most three crashes by signal")
    func diagnosticLine() {
        let crash = DiagnosticSnapshot.Crash(signal: 11, exceptionType: 1, exceptionCode: 2)
        let snapshot = DiagnosticSnapshot(
            begin: Self.begin,
            end: Self.end,
            appVersion: "1.7.0",
            crashes: [crash, crash, DiagnosticSnapshot.Crash(), crash],
            hangCount: 2,
            cpuExceptionCount: 0,
            diskWriteExceptionCount: 1,
            launchDiagnosticCount: 0
        )

        #expect(
            MetricPayloadSummary.line(for: snapshot)
                == "diagnostics \(Self.window) v1.7.0 crashes=4 hangs=2 cpuExceptions=0 diskWrites=1 launches=0 "
                + "crash(signal=11,type=1,code=2) crash(signal=11,type=1,code=2) crash(unknown)"
        )
    }

    @Test("a diagnostic payload without a version or crashes still reports its counts")
    func emptyDiagnosticLine() {
        let snapshot = DiagnosticSnapshot(
            begin: Self.begin,
            end: Self.end,
            appVersion: nil,
            crashes: [],
            hangCount: 0,
            cpuExceptionCount: 0,
            diskWriteExceptionCount: 0,
            launchDiagnosticCount: 0
        )

        #expect(
            MetricPayloadSummary.line(for: snapshot)
                == "diagnostics \(Self.window) crashes=0 hangs=0 cpuExceptions=0 diskWrites=0 launches=0"
        )
    }
}
