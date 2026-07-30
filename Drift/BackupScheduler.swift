import Foundation
import BackgroundTasks
import DriftCore

/// Minimal subset of `BGProcessingTask` that `BackupScheduler.handle(_:)` needs.
/// `BGProcessingTask` is system-allocated and impossible to fabricate in unit
/// tests, so the testable seam takes this protocol instead. Production code
/// passes a real `BGProcessingTask` through `handleBackgroundTask(_:)`.
protocol BackgroundTaskHandle: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: BackgroundTaskHandle {}

/// `BGProcessingTask` isn't marked `Sendable` under Swift 6 strict concurrency,
/// but the BackgroundTasks framework hands the task to the launch handler and
/// never touches it again concurrently — so the unchecked-Sendable box is
/// safe at the framework contract level. Keeping this private avoids it being
/// reused for other (potentially unsafe) cases.
private struct SendableTaskBox: @unchecked Sendable {
    let task: BGProcessingTask
}

/// Owns BGTaskScheduler registration + nightly scheduling for the iCloud backup
/// flow (Section C of `Docs/designs/561-icloud-backup.md`). Fires
/// `BackupService.performBackup()` when the OS launches the task and reschedules
/// the next run on completion regardless of outcome — backoff is iOS's job.
public final class BackupScheduler: @unchecked Sendable {
    /// Must match the identifier in `BGTaskSchedulerPermittedIdentifiers` in
    /// `Drift/Info.plist` exactly. Apple asserts at registration time if the
    /// two diverge.
    public static let taskIdentifier = "com.drift.health.dailyBackup"

    public static let shared = BackupScheduler()

    private static let registeredLock = NSLock()
    nonisolated(unsafe) private static var _registeredIdentifiers: Set<String> = []

    /// Identifiers that `registerBackgroundTask()` has been called for. Tests
    /// assert against this because `BGTaskScheduler` itself exposes no public
    /// API for inspecting registration state. Idempotent under repeat
    /// `registerBackgroundTask()` calls — BGTaskScheduler asserts on
    /// duplicate registration, so we short-circuit before hitting it.
    public static var registeredTaskIdentifiers: Set<String> {
        registeredLock.lock()
        defer { registeredLock.unlock() }
        return _registeredIdentifiers
    }

    private let now: () -> Date
    private let calendar: Calendar
    private let backupRunner: () async throws -> URL
    private let submitter: (BGProcessingTaskRequest) throws -> Void

    public convenience init() {
        self.init(
            now: { Date() },
            calendar: .current,
            backupRunner: { try await BackupService.shared.performBackup() },
            submitter: { try BGTaskScheduler.shared.submit($0) }
        )
    }

    public init(
        now: @escaping () -> Date,
        calendar: Calendar,
        backupRunner: @escaping () async throws -> URL,
        submitter: @escaping (BGProcessingTaskRequest) throws -> Void
    ) {
        self.now = now
        self.calendar = calendar
        self.backupRunner = backupRunner
        self.submitter = submitter
    }

    /// Register the daily backup launch handler with `BGTaskScheduler`. Must
    /// be called once early in app launch — `DriftApp.init()` is the canonical
    /// call site. Idempotent: BGTaskScheduler asserts on duplicate
    /// registration, so subsequent calls in the same process short-circuit
    /// after the first. This matters in unit tests where the test host app
    /// already registered during launch and individual cases may call again.
    public static func registerBackgroundTask() {
        registeredLock.lock()
        let alreadyRegistered = _registeredIdentifiers.contains(taskIdentifier)
        registeredLock.unlock()
        guard !alreadyRegistered else { return }

        _ = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // Swift 6 strict-concurrency doesn't mark `BGProcessingTask` as
            // Sendable, so it can't be captured directly into a `Task`. Box it
            // in a Sendable wrapper to cross the actor boundary; BackgroundTasks
            // owns the lifetime and only calls back into our handler once.
            let boxed = SendableTaskBox(task: processingTask)
            Task {
                await BackupScheduler.shared.handleBackgroundTask(boxed.task)
            }
        }
        registeredLock.lock()
        _registeredIdentifiers.insert(taskIdentifier)
        registeredLock.unlock()
    }

    /// Submit a `BGProcessingTaskRequest` for the next 3 AM device-local fire.
    /// Idempotent — calling again replaces the previously submitted request.
    /// Failures from `BGTaskScheduler.submit` are swallowed; the OS surfaces
    /// the actual cause in console logs and there's no recovery the app can
    /// take at this layer.
    public func scheduleNextBackup() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = nextRunDate()
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? submitter(request)
    }

    /// Drive a fired `BGProcessingTask` to completion. Wires
    /// `expirationHandler` so iOS can cancel cleanly if we overrun, runs
    /// `BackupService.performBackup()`, reports outcome, and reschedules.
    public func handleBackgroundTask(_ task: BGProcessingTask) async {
        await handle(task as BackgroundTaskHandle)
    }

    /// Protocol-typed entry point so tests can inject a stub task. Production
    /// callers should use `handleBackgroundTask(_:)`.
    func handle(_ task: BackgroundTaskHandle) async {
        let runner = Task {
            let ok = await runBackup()
            // Piggyback the social sync on the SAME nightly wake rather than
            // registering a second BGTask identifier: iOS budgets background
            // execution per app, so two tasks compete for one allowance instead
            // of doubling it. This is what lets steps and lift bests reach a
            // friend's board without the owner opening the app that day.
            //
            // Best-effort by nature — iOS decides whether 3am happens at all, so
            // this narrows the gap rather than closing it. The foreground
            // trigger stays the reliable one.
            await SocialSync.onBackgroundRefresh()
            return ok
        }
        task.expirationHandler = { runner.cancel() }
        let success = await runner.value
        task.setTaskCompleted(success: success)
        scheduleNextBackup()
    }

    /// Exposed at internal access so tests can validate the success/failure
    /// branch without driving the full `handle(_:)` glue.
    func runBackup() async -> Bool {
        do {
            _ = try await backupRunner()
            return true
        } catch {
            return false
        }
    }

    /// Next 3 AM device-local from `now()`. Falls back to `now + 24h` if
    /// `Calendar.nextDate(...)` returns nil — defensive, since `.nextTime`
    /// with a fixed-hour matcher is documented to always resolve.
    private func nextRunDate() -> Date {
        var components = DateComponents()
        components.hour = 3
        components.minute = 0
        let next = calendar.nextDate(
            after: now(),
            matching: components,
            matchingPolicy: .nextTime
        )
        return next ?? now().addingTimeInterval(24 * 60 * 60)
    }
}
