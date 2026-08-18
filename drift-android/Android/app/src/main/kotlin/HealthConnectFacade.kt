package drift.android

import android.content.Context
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/// Blocking + JSON facade over Health Connect for the Swift side.
///
/// Health Connect's client API is entirely `suspend` functions, which Skip's
/// AnyDynamicObject reflection bridge cannot call (no Continuation support) —
/// so every entry point here collapses the coroutine with `runBlocking` and
/// returns a JSON string. Callers MUST invoke these off the main thread.
/// Aggregation/grouping happens HERE, not across the bridge, so each call
/// marshals exactly one string.
class HealthConnectFacade {

    companion object {
        /// Registered by MainActivity.onCreate (Activity-lifecycle-bound contract).
        @JvmField
        var permissionLauncher: ActivityResultLauncher<Set<String>>? = null

        /// Permission-sheet result, polled from Swift — an Activity result is
        /// an inherently deferred callback and Skip's bridge can deliver no
        /// Kotlin→Swift callback, so it comes back as companion state (same
        /// shape as CameraCaptureFacade/ImagePickerFacade). Swift builds a
        /// FRESH facade instance per call, so instance fields would be lost.
        /// 0 idle · 1 sheet up · 2 finished.
        @Volatile private var permissionFlowStatus = 0

        /// How many permissions the sheet came back with. -1 = never ran.
        /// Deliberately a COUNT, not a verdict: the sheet can return a partial
        /// grant, and Swift re-derives the truth from `hasAllReadPermissions`
        /// plus the sync that follows.
        @Volatile private var permissionFlowGranted = -1

        /// MainActivity's registered permission callback lands here (main thread).
        fun onPermissionFlowCompleted(grantedCount: Int) {
            permissionFlowGranted = grantedCount
            permissionFlowStatus = 2
        }
    }

    /// What the LAUNCH catch-up treats as "fully granted". Body fat is
    /// deliberately excluded: the launch path re-fires the sheet whenever this
    /// is false, so adding a permission here would re-prompt every cold start
    /// for every user who already granted the seven.
    private val corePermissions = setOf(
        HealthPermission.getReadPermission(WeightRecord::class),
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(HeightRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
    )

    /// Everything a user-initiated "Connect / Sync now" asks for — body fat
    /// included, so body-composition import has a permission to stand on.
    private val readPermissions = corePermissions +
        setOf(HealthPermission.getReadPermission(BodyFatRecord::class))

    private val context: Context
        get() = skip.foundation.ProcessInfo.processInfo.androidContext

    private fun client(): HealthConnectClient = HealthConnectClient.getOrCreate(context)

    private val dayFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

    private fun dayString(instant: Instant): String =
        instant.atZone(ZoneId.systemDefault()).toLocalDate().format(dayFormatter)

    /// Smoke test for the Swift↔Kotlin reflective bridge.
    fun ping(): String = "ok"

    /// 1 = available, 2 = needs provider update/install, 0 = unavailable.
    fun availabilityStatus(): Int =
        when (HealthConnectClient.getSdkStatus(context)) {
            HealthConnectClient.SDK_AVAILABLE -> 1
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> 2
            else -> 0
        }

    /// JSON array of granted health permission strings.
    fun grantedPermissionsJson(): String = runBlocking {
        try {
            val granted = client().permissionController.getGrantedPermissions()
            JSONArray(granted.toList()).toString()
        } catch (e: Exception) {
            JSONArray().toString()
        }
    }

    /// True when every permission the background sync needs is granted.
    fun hasAllPermissions(): Boolean = runBlocking {
        try {
            client().permissionController.getGrantedPermissions().containsAll(corePermissions)
        } catch (e: Exception) {
            false
        }
    }

    /// True when the full ask — core + body fat — is granted.
    fun hasAllReadPermissions(): Boolean = runBlocking {
        try {
            client().permissionController.getGrantedPermissions().containsAll(readPermissions)
        } catch (e: Exception) {
            false
        }
    }

    /// Fires the system permission sheet (contract registered in MainActivity).
    /// MUST be called on the main thread. Returns false when the launcher was
    /// never registered — the caller must not then wait for a result that can
    /// never arrive. The outcome is recovered via `permissionFlowPoll()`.
    fun requestPermissions(): Boolean {
        val launcher = permissionLauncher ?: return false
        permissionFlowGranted = -1
        permissionFlowStatus = 1
        launcher.launch(readPermissions)
        return true
    }

    /// 0 idle · 1 sheet up · 2 finished.
    fun permissionFlowPoll(): Int = permissionFlowStatus

    /// Permissions the last sheet granted; -1 when it never ran. Zero after a
    /// completed flow means the user denied — and once Android marks the
    /// permission USER_FIXED the sheet auto-dismisses, so the button can never
    /// work again and the only way out is Health Connect's own settings.
    fun permissionFlowGrantedCount(): Int = permissionFlowGranted

    /// Open Health Connect where the user can flip our permissions back on —
    /// the only escape once Android has marked a denial USER_FIXED and stopped
    /// showing the sheet. Health Connect is a platform component on API 34+ and
    /// a separate app below it, with different actions and no compile-time
    /// constant for the platform ones, so this walks a candidate chain from
    /// most specific (this app's permission page) to a guaranteed-resolvable
    /// last resort, and takes the first that resolves.
    fun openHealthConnectSettings(): Boolean {
        val packageExtra = "android.intent.extra.PACKAGE_NAME"
        val candidates = listOf(
            Intent("android.health.connect.action.MANAGE_HEALTH_PERMISSIONS")
                .putExtra(packageExtra, context.packageName),
            Intent("androidx.health.connect.action.MANAGE_HEALTH_PERMISSIONS")
                .putExtra(packageExtra, context.packageName),
            Intent("android.health.connect.action.HEALTH_HOME_SETTINGS"),
            // = HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS, spelled out:
            // the androidx constant is a plain string for the pre-34 standalone
            // app, and hard-coding it keeps this chain free of an API whose
            // Kotlin name has moved between releases.
            Intent("androidx.health.connect.action.HEALTH_CONNECT_SETTINGS"),
            Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(android.net.Uri.parse("package:" + context.packageName)),
        )
        for (intent in candidates) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return true
            } catch (e: Exception) {
                // Unresolvable on this OS version — fall through to the next.
            }
        }
        return false
    }

    /// Body-fat records in [startMillis, endMillis):
    /// [{"date":"yyyy-MM-dd","pct":23.4}] — one entry per day, LATEST wins,
    /// same shape as readWeightsJson. Health Connect's Percentage is already
    /// 0-100, unlike HealthKit's 0.0-1.0 — do NOT rescale on the Swift side.
    fun readBodyFatJson(startMillis: Long, endMillis: Long): String = runBlocking {
        val out = JSONArray()
        try {
            val latestPerDay = LinkedHashMap<String, BodyFatRecord>()
            var pageToken: String? = null
            do {
                val response = client().readRecords(
                    ReadRecordsRequest(
                        recordType = BodyFatRecord::class,
                        timeRangeFilter = TimeRangeFilter.between(
                            Instant.ofEpochMilli(startMillis), Instant.ofEpochMilli(endMillis)
                        ),
                        pageToken = pageToken,
                    )
                )
                for (record in response.records) {
                    val day = dayString(record.time)
                    val existing = latestPerDay[day]
                    if (existing == null || record.time.isAfter(existing.time)) {
                        latestPerDay[day] = record
                    }
                }
                pageToken = response.pageToken
            } while (pageToken != null)

            for ((day, record) in latestPerDay) {
                out.put(JSONObject().apply {
                    put("date", day)
                    put("pct", record.percentage.value)
                })
            }
        } catch (e: Exception) {
            // permission denied / provider missing → empty result, never throw
        }
        out.toString()
    }

    /// Weight records in [startMillis, endMillis):
    /// [{"date":"yyyy-MM-dd","kg":72.5,"tMillis":..., "origin":"com.foo.scale"}]
    /// One entry per day — the LATEST record wins (mirrors the iOS sync).
    fun readWeightsJson(startMillis: Long, endMillis: Long): String = runBlocking {
        val out = JSONArray()
        try {
            val latestPerDay = LinkedHashMap<String, WeightRecord>()
            var pageToken: String? = null
            do {
                val response = client().readRecords(
                    ReadRecordsRequest(
                        recordType = WeightRecord::class,
                        timeRangeFilter = TimeRangeFilter.between(
                            Instant.ofEpochMilli(startMillis), Instant.ofEpochMilli(endMillis)
                        ),
                        pageToken = pageToken,
                    )
                )
                for (record in response.records) {
                    val day = dayString(record.time)
                    val existing = latestPerDay[day]
                    if (existing == null || record.time.isAfter(existing.time)) {
                        latestPerDay[day] = record
                    }
                }
                pageToken = response.pageToken
            } while (pageToken != null)

            for ((day, record) in latestPerDay) {
                out.put(JSONObject().apply {
                    put("date", day)
                    put("kg", record.weight.inKilograms)
                    put("tMillis", record.time.toEpochMilli())
                    put("origin", record.metadata.dataOrigin.packageName)
                })
            }
        } catch (e: Exception) {
            // permission denied / provider missing → empty result, never throw
        }
        out.toString()
    }

    /// Total steps for one local day: {"steps": 8123.0}
    fun readStepsJson(dayStartMillis: Long, dayEndMillis: Long): String = runBlocking {
        val obj = JSONObject()
        try {
            var total = 0L
            var pageToken: String? = null
            do {
                val response = client().readRecords(
                    ReadRecordsRequest(
                        recordType = StepsRecord::class,
                        timeRangeFilter = TimeRangeFilter.between(
                            Instant.ofEpochMilli(dayStartMillis), Instant.ofEpochMilli(dayEndMillis)
                        ),
                        pageToken = pageToken,
                    )
                )
                for (record in response.records) total += record.count
                pageToken = response.pageToken
            } while (pageToken != null)
            obj.put("steps", total.toDouble())
        } catch (e: Exception) {
            obj.put("steps", 0.0)
        }
        obj.toString()
    }

    /// Calories burned for one local day: {"active": 512.0, "total": 2200.0} (kcal)
    fun readCaloriesJson(dayStartMillis: Long, dayEndMillis: Long): String = runBlocking {
        val obj = JSONObject()
        val filter = TimeRangeFilter.between(
            Instant.ofEpochMilli(dayStartMillis), Instant.ofEpochMilli(dayEndMillis)
        )
        try {
            var active = 0.0
            var pageToken: String? = null
            do {
                val response = client().readRecords(
                    ReadRecordsRequest(recordType = ActiveCaloriesBurnedRecord::class, timeRangeFilter = filter, pageToken = pageToken)
                )
                for (record in response.records) active += record.energy.inKilocalories
                pageToken = response.pageToken
            } while (pageToken != null)

            var total = 0.0
            pageToken = null
            do {
                val response = client().readRecords(
                    ReadRecordsRequest(recordType = TotalCaloriesBurnedRecord::class, timeRangeFilter = filter, pageToken = pageToken)
                )
                for (record in response.records) total += record.energy.inKilocalories
                pageToken = response.pageToken
            } while (pageToken != null)

            obj.put("active", active)
            obj.put("total", total)
        } catch (e: Exception) {
            obj.put("active", 0.0)
            obj.put("total", 0.0)
        }
        obj.toString()
    }

    /// Sleep sessions overlapping [startMillis, endMillis):
    /// [{"date":"yyyy-MM-dd","hours":7.4}] — date = session END day, summed per day.
    fun readSleepJson(startMillis: Long, endMillis: Long): String = runBlocking {
        val out = JSONArray()
        try {
            val hoursPerDay = LinkedHashMap<String, Double>()
            var pageToken: String? = null
            do {
                val response = client().readRecords(
                    ReadRecordsRequest(
                        recordType = SleepSessionRecord::class,
                        timeRangeFilter = TimeRangeFilter.between(
                            Instant.ofEpochMilli(startMillis), Instant.ofEpochMilli(endMillis)
                        ),
                        pageToken = pageToken,
                    )
                )
                for (record in response.records) {
                    val day = dayString(record.endTime)
                    val hours = (record.endTime.toEpochMilli() - record.startTime.toEpochMilli()) / 3_600_000.0
                    hoursPerDay[day] = (hoursPerDay[day] ?: 0.0) + hours
                }
                pageToken = response.pageToken
            } while (pageToken != null)

            for ((day, hours) in hoursPerDay) {
                out.put(JSONObject().apply {
                    put("date", day)
                    put("hours", hours)
                })
            }
        } catch (e: Exception) {
            // → empty
        }
        out.toString()
    }

    /// Human label for a session with no title, from the symbolic
    /// EXERCISE_TYPE_* constant — never a raw int code. A generic "Workout"
    /// fallback beats a wrong label for the ~60 types we don't special-case.
    private fun exerciseTypeLabel(type: Int): String = when (type) {
        ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING -> "Strength Training"
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING -> "Running"
        ExerciseSessionRecord.EXERCISE_TYPE_WALKING -> "Walking"
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING -> "Biking"
        ExerciseSessionRecord.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING -> "HIIT"
        ExerciseSessionRecord.EXERCISE_TYPE_YOGA -> "Yoga"
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL -> "Swimming"
        ExerciseSessionRecord.EXERCISE_TYPE_ELLIPTICAL -> "Elliptical"
        else -> "Workout"
    }

    /// Exercise sessions in [startMillis, endMillis), each paired with its
    /// active calories over the same interval:
    /// [{"id":"...","type":"Strength Training","durationSec":2700.0,"calories":312.0,"startMillis":...}]
    fun readWorkoutsJson(startMillis: Long, endMillis: Long): String = runBlocking {
        val out = JSONArray()
        try {
            val sessions = mutableListOf<ExerciseSessionRecord>()
            var pageToken: String? = null
            do {
                val response = client().readRecords(
                    ReadRecordsRequest(
                        recordType = ExerciseSessionRecord::class,
                        timeRangeFilter = TimeRangeFilter.between(
                            Instant.ofEpochMilli(startMillis), Instant.ofEpochMilli(endMillis)
                        ),
                        pageToken = pageToken,
                    )
                )
                sessions.addAll(response.records)
                pageToken = response.pageToken
            } while (pageToken != null)

            for (session in sessions) {
                val caloriesFilter = TimeRangeFilter.between(session.startTime, session.endTime)
                var calories = 0.0
                var caloriesPageToken: String? = null
                do {
                    val caloriesResponse = client().readRecords(
                        ReadRecordsRequest(recordType = ActiveCaloriesBurnedRecord::class, timeRangeFilter = caloriesFilter, pageToken = caloriesPageToken)
                    )
                    for (record in caloriesResponse.records) calories += record.energy.inKilocalories
                    caloriesPageToken = caloriesResponse.pageToken
                } while (caloriesPageToken != null)

                val label = session.title?.takeIf { it.isNotBlank() } ?: exerciseTypeLabel(session.exerciseType)
                out.put(JSONObject().apply {
                    put("id", session.metadata.id)
                    put("type", label)
                    put("durationSec", (session.endTime.toEpochMilli() - session.startTime.toEpochMilli()) / 1000.0)
                    put("calories", calories)
                    put("startMillis", session.startTime.toEpochMilli())
                })
            }
        } catch (e: Exception) {
            // permission denied / provider missing → empty result, never throw
        }
        out.toString()
    }

    /// DEBUG/e2e only: seed a weight record so the read pipeline can be
    /// verified on an emulator. Needs WRITE_WEIGHT, which only the debug
    /// manifest overlay declares — in release this throws SecurityException
    /// and returns false.
    fun debugSeedWeight(kg: Double, epochMillis: Long): Boolean = runBlocking {
        try {
            val record = WeightRecord(
                time = Instant.ofEpochMilli(epochMillis),
                zoneOffset = null,
                weight = androidx.health.connect.client.units.Mass.kilograms(kg),
                metadata = androidx.health.connect.client.records.metadata.Metadata.manualEntry(),
            )
            client().insertRecords(listOf(record))
            true
        } catch (e: Exception) {
            false
        }
    }

    /// DEBUG/e2e only: seed a body-fat record so the body-composition import
    /// can be verified on an emulator. Needs WRITE_BODY_FAT (debug manifest
    /// overlay only) — release throws SecurityException and returns false.
    fun debugSeedBodyFat(pct: Double, epochMillis: Long): Boolean = runBlocking {
        try {
            val record = BodyFatRecord(
                time = Instant.ofEpochMilli(epochMillis),
                zoneOffset = null,
                percentage = androidx.health.connect.client.units.Percentage(pct),
                metadata = androidx.health.connect.client.records.metadata.Metadata.manualEntry(),
            )
            client().insertRecords(listOf(record))
            true
        } catch (e: Exception) {
            false
        }
    }

    /// DEBUG/e2e only: seed one 45-minute strength-training session ending
    /// now, plus ~300kcal of active calories over the same interval, so the
    /// Workout tab's Health Connect band can be verified on an emulator.
    /// Needs WRITE_EXERCISE, debug-manifest-only — release throws
    /// SecurityException and returns false.
    fun debugSeedExerciseSession(): Boolean = runBlocking {
        try {
            val end = Instant.now()
            val start = end.minusSeconds(45 * 60)
            val session = ExerciseSessionRecord(
                startTime = start,
                startZoneOffset = null,
                endTime = end,
                endZoneOffset = null,
                exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING,
                metadata = androidx.health.connect.client.records.metadata.Metadata.manualEntry(),
            )
            val calories = ActiveCaloriesBurnedRecord(
                startTime = start,
                startZoneOffset = null,
                endTime = end,
                endZoneOffset = null,
                energy = androidx.health.connect.client.units.Energy.kilocalories(300.0),
                metadata = androidx.health.connect.client.records.metadata.Metadata.manualEntry(),
            )
            client().insertRecords(listOf(session, calories))
            true
        } catch (e: Exception) {
            false
        }
    }

    /// Most recent height in cm, or -1.0 when none/denied.
    fun readLatestHeightCm(): Double = runBlocking {
        try {
            val response = client().readRecords(
                ReadRecordsRequest(
                    recordType = HeightRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(Instant.EPOCH, Instant.now()),
                    ascendingOrder = false,
                    pageSize = 1,
                )
            )
            response.records.firstOrNull()?.height?.inMeters?.times(100.0) ?: -1.0
        } catch (e: Exception) {
            -1.0
        }
    }
}
