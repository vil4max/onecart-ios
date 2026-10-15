import Foundation

/// Unstructured workers let the caller finish even when an SDK callback ignores cancellation.
enum CloudKitDeadline {
    static func run<Value: Sendable>(
        timeoutNanoseconds: UInt64,
        timeoutError: Error = OneCartCloudKitError.shareTimedOut,
        onLateCompletion: (@Sendable (Result<Value, Error>) -> Void)? = nil,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await run(
            timeout: { try await Task.sleep(nanoseconds: timeoutNanoseconds) },
            timeoutError: timeoutError,
            onLateCompletion: onLateCompletion,
            operation: operation
        )
    }

    /// `onLateCompletion` runs at most once, with the operation's own result, when the operation
    /// finishes after the caller was already released by the timeout or by cancellation. A late
    /// cloud write is still a write: the caller learns it happened instead of guessing.
    static func run<Value: Sendable>(
        timeout: @escaping @Sendable () async throws -> Void,
        timeoutError: Error = OneCartCloudKitError.shareTimedOut,
        onLateCompletion: (@Sendable (Result<Value, Error>) -> Void)? = nil,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let gate = DeadlineResultGate<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                let work = Task {
                    let result: Result<Value, Error>
                    do { result = .success(try await operation()) } catch { result = .failure(error) }
                    if !gate.resolve(result) {
                        onLateCompletion?(result)
                    }
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

/// `@unchecked Sendable`: every mutable field is read and written only under `lock`.
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

    /// Returns whether this call settled the caller; only the first result does.
    @discardableResult
    func resolve(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return false
        }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        let tasks = tasks
        self.tasks = []
        lock.unlock()
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
        return true
    }
}
