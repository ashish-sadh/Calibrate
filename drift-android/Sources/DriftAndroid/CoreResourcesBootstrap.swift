import Foundation
import SkipFuse

/// Installs DriftCore's seed resources where its `Bundle.module` accessor
/// looks on Android. Skip packages only the app module's resources into the
/// APK, so scripts/android-sync-core-resources.sh mirrors DriftCore's seeds
/// into this module (Resources/DriftCoreSeed/), and this copies them on first
/// launch to `<files>/DriftCore_DriftCore.resources/` — the first candidate
/// path of the SwiftPM-generated resource accessor.
enum CoreResourcesBootstrap {
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
