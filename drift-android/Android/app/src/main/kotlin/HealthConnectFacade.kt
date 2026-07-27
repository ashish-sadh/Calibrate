package drift.android

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
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
    }

    private val readPermissions = setOf(
        HealthPermission.getReadPermission(WeightRecord::class),
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(HeightRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
    )

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

    /// True when every read permission this app uses is granted.
    fun hasAllPermissions(): Boolean = runBlocking {
        try {
            client().permissionController.getGrantedPermissions().containsAll(readPermissions)
        } catch (e: Exception) {
            false
        }
    }

    /// Fires the system permission sheet (contract registered in MainActivity).
    fun requestPermissions() {
        permissionLauncher?.launch(readPermissions)
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
