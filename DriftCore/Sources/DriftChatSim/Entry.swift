import Foundation
import DriftCore

// DriftChatSim — a macOS-hosted simulator that drives the REAL Drift chat
// pipeline (StaticOverrides + AIToolAgent + real tools) against a seeded sample
// DB, so we can run conversations from a terminal, see exactly where each turn
// routes, and harden the harness fast.
//
//   swift run DriftChatSim --once "log 250ml water"
//   swift run DriftChatSim --repl
//   swift run DriftChatSim --script turns.json --json
//
// Backend: auto (Nebius if NEBIUS_API_KEY set, else local Gemma if present,
// else deterministic-only). Override with --backend nebius|local|auto.

@main
struct Main {
    @MainActor
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())

        if args.contains("--help") || args.contains("-h") { printUsage(); return }

        let json = pluck(&args, flag: "--json")
        let noSeed = pluck(&args, flag: "--no-seed")
        let backend = pluckValue(&args, flag: "--backend") ?? "auto"
        let screenName = pluckValue(&args, flag: "--screen") ?? "dashboard"
        let modelPath = pluckValue(&args, flag: "--model")
        let screen = AIScreen(rawValue: screenName) ?? .dashboard

        // Boot the pipeline.
        ToolRegistration.registerAll()
        let backendLabel = installBackend(backend, modelPath: modelPath)
        ChatSim.backendLabel = backendLabel
        let allowAgent = !backendLabel.hasPrefix("none")

        if !noSeed {
            do { try Seed.sampleDB() }
            catch { err("seed failed: \(error)"); return }
        }

        printBanner(backendLabel: backendLabel, screen: screen, seeded: !noSeed, allowAgent: allowAgent)

        // Mode dispatch.
        if let i = args.firstIndex(of: "--once") {
            let msg = i + 1 < args.count ? args[i + 1] : ""
            guard !msg.isEmpty else { err("--once needs a message"); return }
            let t = await ChatSim.runTurn(msg, screen: screen, history: "", allowAgent: allowAgent)
            emit(t, json: json)
        } else if let i = args.firstIndex(of: "--script") {
            let path = i + 1 < args.count ? args[i + 1] : ""
            await runScript(path, screen: screen, allowAgent: allowAgent, json: json)
        } else {
            await runREPL(screen: screen, allowAgent: allowAgent, json: json)
        }

        // llama.cpp's Metal device singleton crashes (SIGABRT) in its C++ static
        // destructor during normal exit() teardown. The turn(s) already ran and
        // output is flushed, so skip atexit/destructors entirely with _exit — the
        // OS reclaims everything. Without this the process returns 134 even on success.
        fflush(stdout)
        _exit(0)
    }

    // MARK: - Modes

    @MainActor
    static func runREPL(screen: AIScreen, allowAgent: Bool, json: Bool) async {
        var history = ""
        print("REPL ready. Type a message, or :help for meta-commands.\n")
        while let line = readLine() {
            let input = line.trimmingCharacters(in: .whitespaces)
            if input.isEmpty { continue }
            if input.hasPrefix(":") {
                if handleMeta(input) { continue } else { break }  // :quit returns false
            }
            let t = await ChatSim.runTurn(input, screen: screen, history: history, allowAgent: allowAgent)
            emit(t, json: json)
            history += "Q: \(t.input)\nA: \(t.response)\n"
        }
    }

    @MainActor
    static func runScript(_ path: String, screen: AIScreen, allowAgent: Bool, json: Bool) async {
        guard let data = FileManager.default.contents(atPath: path),
              let script = try? JSONDecoder().decode(ScriptFile.self, from: data) else {
            err("could not read/parse script: \(path)"); return
        }
        var history = ""
        for turn in script.turns {
            if let spec = turn.setPhase, let phase = ChatSim.parsePhase(spec) {
                ConversationState.shared.phase = phase
            }
            let t = await ChatSim.runTurn(turn.input, screen: screen, history: history, allowAgent: allowAgent)
            emit(t, json: json)
            history += "Q: \(t.input)\nA: \(t.response)\n"
        }
    }

    /// Returns false only for :quit (caller breaks the loop).
    @MainActor
    static func handleMeta(_ input: String) -> Bool {
        let parts = input.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        switch parts.first {
        case "quit", "q": return false
        case "help":
            print(":phase <spec>   force ConversationState (e.g. :phase planningMeals:lunch:0)")
            print(":state          show phase / turn / today's nutrition")
            print(":reseed         factoryReset + reseed the sample DB")
            print(":quit           exit")
        case "phase":
            if parts.count > 1, let p = ChatSim.parsePhase(parts[1]) {
                ConversationState.shared.phase = p
                print("phase → \(ChatSim.describePhase(p))")
            } else { print("usage: :phase planningMeals:lunch:0  (or idle, awaitingMealItems:lunch)") }
        case "state":
            let s = ChatSim.DBSnapshot.capture()
            print("phase=\(ChatSim.describePhase(ConversationState.shared.phase)) turn=\(ConversationState.shared.turnCount) lastTool=\(ConversationState.shared.lastTool ?? "-")")
            print("today: \(Int(s.calories)) cal, \(s.foodEntries) food rows, \(s.weightEntries) weight rows")
        case "reseed":
            do { try Seed.sampleDB(); print("reseeded.") } catch { print("reseed failed: \(error)") }
        default:
            print("unknown meta-command. :help for the list.")
        }
        return true
    }

    // MARK: - Backend install

    @MainActor
    static func installBackend(_ choice: String, modelPath: String?) -> String {
        let env = ProcessInfo.processInfo.environment

        func nebius() -> String? {
            guard let key = env["NEBIUS_API_KEY"], !key.isEmpty else { return nil }
            let model = env["NEBIUS_MODEL_ID"] ?? "Qwen/Qwen3-235B-A22B-Instruct-2507"
            LocalAIService.shared.useRemoteBackend(provider: .nebius, modelID: model, apiKey: key)
            return "remote(.nebius, \(model))"
        }
        func local() -> String? {
            let raw = modelPath ?? env["DRIFT_MODEL_PATH"]
                ?? (NSString(string: "~/drift-state/models/gemma-4-e2b-q4_k_m.gguf").expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: raw) else { return nil }
            do {
                try LocalAIService.shared.useLocalBackend(modelPath: URL(fileURLWithPath: raw))
                return "local(\(URL(fileURLWithPath: raw).lastPathComponent))"
            } catch {
                err("local backend load failed: \(error)")
                return nil
            }
        }

        switch choice {
        case "nebius": return nebius() ?? "none (NEBIUS_API_KEY not set)"
        case "local":  return local() ?? "none (local model missing or failed to load)"
        default:       return nebius() ?? local() ?? "none (deterministic-only)"
        }
    }

    // MARK: - Output

    @MainActor
    static func emit(_ t: ChatSim.TurnTrace, json: Bool) {
        print(json ? TracePrinter.json(t) : TracePrinter.human(t))
    }

    static func printBanner(backendLabel: String, screen: AIScreen, seeded: Bool, allowAgent: Bool) {
        print("""
        ┌─ DriftChatSim ────────────────────────────────────────────
        │ backend : \(backendLabel)
        │ screen  : \(screen.rawValue)\(seeded ? "   DB: seeded sample (lose-weight goal, Indian day)" : "   DB: existing (--no-seed)")
        │ COVERS  : normalize → StaticOverrides (Phase 1) → AIToolAgent (Phase 8) + real tools + real DB
        │ GAP     : iOS dispatch Phases 0.5–7 (multi-turn picks, food-intent parse, confirms) are NOT here —
        │           the bare-"1" meal-plan pick is NOT reproducible end-to-end in v1. Use :phase to stage state
        │           and watch static_override swallow it (the bug's mechanism), pending the v2 ChatEngine.
        └───────────────────────────────────────────────────────────
        """)
        if !allowAgent {
            err("⚠️  No backend — running deterministic-only (static overrides + tools). Set NEBIUS_API_KEY or place the Gemma gguf to exercise the LLM agent.")
        }
    }

    static func printUsage() {
        print("""
        DriftChatSim — drive the real Drift chat pipeline over a seeded DB.

        USAGE:
          swift run DriftChatSim [--once "msg" | --script file.json | (repl, default)]
                                 [--backend nebius|local|auto] [--screen NAME]
                                 [--model PATH] [--no-seed] [--json]

        BACKENDS:
          auto (default)  Nebius if NEBIUS_API_KEY set, else local Gemma, else deterministic-only
          nebius          NEBIUS_API_KEY (+ optional NEBIUS_MODEL_ID) env
          local           ~/drift-state/models/gemma-4-e2b-q4_k_m.gguf (or --model / DRIFT_MODEL_PATH)

        SCRIPT FILE: { "turns": [ {"input": "...", "setPhase": "planningMeals:lunch:0"} ] }
        REPL meta:   :phase <spec>  :state  :reseed  :quit
        """)
    }

    // MARK: - Arg helpers

    static func pluck(_ args: inout [String], flag: String) -> Bool {
        guard let i = args.firstIndex(of: flag) else { return false }
        args.remove(at: i); return true
    }

    static func pluckValue(_ args: inout [String], flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        args.removeSubrange(i...(i + 1)); return v
    }

    static func err(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }
}

struct ScriptFile: Decodable { let turns: [ScriptTurn] }
struct ScriptTurn: Decodable { let input: String; let setPhase: String? }
