package drift.android

import android.content.Context

/// Forces a synchronous flush of the "defaults" SharedPreferences to disk.
/// SkipFoundation's UserDefaults writes every value via apply() (async) and
/// its synchronize() is a no-op; on this build the async flush never durably
/// lands (#1108). commit() rewrites the full in-memory map inline, so one call
/// persists every pending write. Same context + same "defaults" name as
/// UserDefaults(suiteName: nil), so it flushes exactly those writes.
class AndroidPrefsFacade {
    private val context: Context
        get() = skip.foundation.ProcessInfo.processInfo.androidContext

    fun flush(): Boolean =
        context.getSharedPreferences("defaults", Context.MODE_PRIVATE).edit().commit()
}
