import Foundation
import SkipFuse
import DriftCore

/// Installs DriftCore's seed resources where its `Bundle.module` accessor
/// looks on Android. Skip packages only the app module's resources into the
/// APK, so scripts/android-sync-core-resources.sh mirrors DriftCore's seeds
/// into this module (Resources/DriftCoreSeed/), and this copies them on first
/// launch to `<files>/DriftCore_DriftCore.resources/` — the first candidate
/// path of the SwiftPM-generated resource accessor.
enum CoreResourcesBootstrap {
    /// True once the one-time warm-up has finished — views use this to skip
    /// their loading gate entirely instead of re-awaiting.
    @MainActor static private(set) var isWarm = false

    /// The warm-up runs EXACTLY ONCE per process (static-let task). Before
    /// this, every warmUpDatabase() call re-ran install() — re-reading the
    /// multi-MB seed files to compare sizes on every tab visit, which is why
    /// the Food tab spinner lingered on each entry.
    private static let warmTask: Task<Void, Never> = Task.detached(priority: .userInitiated) {
        install()
        _ = try? AppDatabase.shared.searchFoods(query: "warmup", limit: 1)
        // The shared DB is now open off-main — prime the durable key-value cache
        // (#1108) here, before isWarm flips, so views that gate on warmth read
        // persisted settings/goal directly instead of transient defaults.
        (DriftPlatform.keyValueStore as? DbKeyValueStore)?.prime()
        // #941 idempotent upgrade: back-fills muscle slugs + pose assets onto
        // template custom exercises registered by older builds. iOS runs it at
        // every launch (DriftApp.swift:99); Android had it only as a side
        // effect of DefaultTemplates.load() (DefaultTemplates.swift:68), i.e.
        // only if the user tapped "load package" in WorkoutView — so templates
        // from an older build kept missing muscles and photos forever (#1214).
        // Here rather than on the main actor: it decodes the ~1 MB exercises.json
        // catalog, which install() above has already staged, so the read is warm
        // and the cost lands off-main, before isWarm opens the UI gates.
        //
        // Ordered before the prune to mirror iOS (:99 then :100). That is
        // mirror-fidelity, not a data dependency — both are idempotent and
        // operate on disjoint sets (template customs vs pre-#1079 raw-utterance
        // customs), so don't "fix" the order later thinking one feeds the other.
        DefaultTemplates.registerCustomExercises()
        // #1107: one-time cleanup of legacy raw-utterance custom exercises
        // (pre-#1079 parser bug) — needs the KV cache primed above.
        WorkoutService.pruneLegacyUtteranceCustomExercisesOnce()
        await MainActor.run { isWarm = true }
    }

    /// Kick the one-time warm task WITHOUT awaiting it (#1240).
    ///
    /// `warmTask` is a lazy static, so the off-main open does not begin until
    /// something first touches it. Call this once the DriftPlatform seams are
    /// installed (end of `onInit`) so the open is already in flight before any
    /// MainActor lifecycle task can run — that shrinks the window in which an
    /// un-audited path could become the first toucher of `AppDatabase.shared`
    /// on the main thread. Idempotent; this does NOT replace the ordering
    /// contract — every launch-path task must still `await warmUpDatabase()`
    /// before touching the database.
    static func beginWarmUp() {
        // Logged with the calling thread on purpose: this runs from
        // Application.onCreate (main), so it is the positive control for the
        // main-thread tripwire in AppDatabase.makeShared — that one must
        // report OFF-main on the same launch (#1240).
        Log.app.info("Warm-up kicked from mainThread=\(Thread.isMainThread) — #1240")
        _ = warmTask
    }

    /// Force the first AppDatabase open (migrate + food seed) OFF the main
    /// thread — @MainActor services (FoodService/WeightServiceAPI) are then
    /// cheap to call on main because the heavy one-time work is done.
    /// Awaiting after the first completion returns immediately.
    static func warmUpDatabase() async {
        await warmTask.value
    }

    static let seedFiles = ["foods.json", "exercises.json", "biomarkers.json", "bodyDiagram.json"]

    /// Idempotent; call before the first touch of `AppDatabase.shared`.
    static func install() {
        #if os(Android)
        var log: [String] = []
        log.append("home=\(NSHomeDirectory()) bundlePath=\(Bundle.main.bundlePath)")

        // NSHomeDirectory() on Android is already the app's files/ dir — the
        // exact location DriftCore's resource accessor probes.
        let filesDir = URL(fileURLWithPath: NSHomeDirectory())
        let destDir = filesDir.appendingPathComponent("DriftCore_DriftCore.resources", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            for name in seedFiles {
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                let src = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "DriftCoreSeed")
                    ?? Bundle.module.url(forResource: "DriftCoreSeed/\(base)", withExtension: ext)
                    ?? Bundle.module.url(forResource: base, withExtension: ext)
                guard let src else {
                    log.append("MISSING \(name); module bundle=\(Bundle.module.bundlePath)")
                    continue
                }
                let dest = destDir.appendingPathComponent(name)
                do {
                    let data = try Data(contentsOf: src)
                    if let existing = try? Data(contentsOf: dest), existing.count == data.count {
                        log.append("ok \(name) (cached, \(data.count)B)")
                        continue
                    }
                    try data.write(to: dest, options: .atomic)
                    log.append("copied \(name) (\(data.count)B) from \(src)")
                } catch {
                    log.append("FAILED \(name): \(error)")
                }
            }
        } catch {
            log.append("mkdir failed: \(error)")
        }
        try? log.joined(separator: "\n").write(
            to: filesDir.appendingPathComponent("bootstrap.log"), atomically: true, encoding: .utf8)
        #endif
    }
}
