import Foundation

/// Unstructured workers let the caller finish even when an SDK callback ignores cancellation.
enum CloudKitDeadline {
    static func run<Value: Sendable>(
        timeoutNanoseconds: UInt64,
        timeoutError: Error = OneCartCloudKitError.shareTimedOut,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await run(
            timeout: { try await Task.sleep(nanoseconds: timeoutNanoseconds) },
            timeoutError: timeoutError,
            operation: operation
        )
    }

    static func run<Value: Sendable>(
        timeout: @escaping @Sendable () async throws -> Void,
        timeoutError: Error = OneCartCloudKitError.shareTimedOut,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let gate = DeadlineResultGate<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                let work = Task {
                    do { try await gate.resolve(.success(operation())) } catch { gate.resolve(.failure(error)) }
                }
                let timer = Task {
                    do {
                        try await timeout()
                        try Task.checkCancellation()
                        gate.resolve(.failure(timeoutError))
                    } catch {}
                }
                gate.setTasks([work, timer])
            }
        } onCancel: {
            gate.resolve(.failure(CancellationError()))
        }
    }
}

private final class DeadlineResultGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func setTasks(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        let finished = result != nil
        if !finished {
            self.tasks = tasks
        }
        lock.unlock()
        if finished {
            tasks.forEach { $0.cancel() }
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        let tasks = tasks
        self.tasks = []
        lock.unlock()
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
