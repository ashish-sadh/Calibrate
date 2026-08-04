#if os(Android)
// Deliberately imports NOTHING but Android. Foundation re-exports Bionic's
// `stdout`, and Swift 6 rejects that imported mutable global as shared mutable
// state — @preconcurrency only silences it for the module the declaration
// actually resolves through, so this file has to keep Foundation out.
@preconcurrency import Android
#endif

/// Line-buffers stdout so `print()` reaches the stdout→logcat relay Main.kt
/// installs (#1081) as each line is written. Bionic buffers stdout fully when
/// it isn't a tty — and after the relay's `dup2` it is a pipe — so without this
/// output would sit in a 4KB clump and look like nothing was logged at all.
///
/// Call once at startup. No-op off Android.
func lineBufferStandardOutput() {
    #if os(Android)
    setvbuf(stdout, nil, _IOLBF, 0)
    #endif
}
