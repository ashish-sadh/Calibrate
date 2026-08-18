package drift.android

import skip.lib.*
import skip.model.*
import skip.foundation.*
import skip.ui.*

import android.Manifest
import android.app.Application
import android.graphics.Color as AndroidColor
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.ComponentActivity
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.MaterialTheme
import androidx.core.app.ActivityCompat

internal val logger: SkipLogger = SkipLogger(subsystem = "drift.android", category = "DriftAndroid")

private typealias AppRootView = DriftAndroidRootView
private typealias AppDelegate = DriftAndroidAppDelegate

/// AndroidAppMain is the `android.app.Application` entry point, and must match `application android:name` in the AndroidMainfest.xml file.
open class AndroidAppMain: Application {
    constructor() {
    }

    override fun onCreate() {
        super.onCreate()
        // Drift is a light-only app by design — iOS pins this at DriftApp.swift:53
        // (.preferredColorScheme(.light)). Pin the whole process light BEFORE any
        // activity inflates, so the DayNight window background, isSystemInDarkTheme()
        // and every AppCompat context resolve light even when the system is dark.
        // Without this, uncoloured Text inherits Material's dark `onSurface` and
        // renders white-on-white (#1228).
        androidx.appcompat.app.AppCompatDelegate.setDefaultNightMode(
            androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_NO)
        startStdioRelay()
        logger.info("starting app")
        ProcessInfo.launch(applicationContext)
        AppDelegate.shared.onInit()
    }

    /// Android throws away a process's stdout/stderr, so every Swift `print()`
    /// — and any `fatalError` message, which goes to the unbuffered fd 2 — is
    /// invisible in logcat (#1081). Point both fds at a pipe and pump each line
    /// back out through android.util.Log. Runs before anything else in the app
    /// so startup output is captured too. DriftCore's structured `Log.*` goes
    /// straight to liblog and does not depend on this relay.
    private fun startStdioRelay() {
        try {
            val pipe = android.system.Os.pipe()
            android.system.Os.dup2(pipe[1], 1)
            android.system.Os.dup2(pipe[1], 2)
            val relay = Thread({
                try {
                    java.io.FileInputStream(pipe[0]).bufferedReader().forEachLine { line ->
                        android.util.Log.i(STDIO_TAG, line)
                    }
                } catch (e: Throwable) {
                    android.util.Log.w(STDIO_TAG, "relay stopped: ${e}")
                }
            }, "drift-stdio-relay")
            relay.isDaemon = true
            relay.start()
        } catch (e: Throwable) {
            android.util.Log.w(STDIO_TAG, "relay unavailable: ${e}")
        }
    }

    companion object {
        private val STDIO_TAG = "com.drift.health/stdio"
    }
}

/// AndroidAppMain is initial `androidx.appcompat.app.AppCompatActivity`, and must match `activity android:name` in the AndroidMainfest.xml file.
open class MainActivity: AppCompatActivity {
    constructor() {
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        logger.info("starting activity")
        UIApplication.launch(this)
        enableEdgeToEdge()

        // Health Connect permission sheet — the contract MUST be registered
        // before the activity reaches STARTED, so it lives here rather than in
        // the facade. HealthConnectFacade.requestPermissions() launches it.
        HealthConnectFacade.permissionLauncher = registerForActivityResult(
            androidx.health.connect.client.PermissionController.createRequestPermissionResultContract()
        ) { granted ->
            logger.info("Health Connect permissions granted: ${granted.size}")
            // Hand the result to the facade's companion so the Swift side can
            // poll it — without this the sync races the sheet and reads
            // permissions the user hasn't granted yet (#1207).
            HealthConnectFacade.onPermissionFlowCompleted(granted.size)
        }

        // Photo Picker (image-in seam #1128) — same rule as above: the contract
        // must be registered before the activity reaches STARTED, so it lives
        // here. ImagePickerFacade.launch() fires it; the result flows back
        // through companion state that the Swift side polls.
        ImagePickerFacade.pickLauncher = registerForActivityResult(
            androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia()
        ) { uri ->
            ImagePickerFacade.onPicked(uri)
        }

        // Document picker (file-in seam #1175) — SAF OpenDocument, the CSV
        // half of "Import from Strong / Hevy". Same registration rule and same
        // polled-companion result path as the photo picker above.
        DocumentPickerFacade.openLauncher = registerForActivityResult(
            androidx.activity.result.contract.ActivityResultContracts.OpenDocument()
        ) { uri ->
            DocumentPickerFacade.onPicked(uri)
        }

        // Camera capture — "Take Photo" half of Snap meal logging (#1111).
        // Same deferred-callback shape as the two contracts above.
        CameraCaptureFacade.cameraLauncher = registerForActivityResult(
            androidx.activity.result.contract.ActivityResultContracts.TakePicture()
        ) { success ->
            CameraCaptureFacade.onCaptured(success)
        }
        CameraCaptureFacade.permissionLauncher = registerForActivityResult(
            androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
        ) { granted ->
            CameraCaptureFacade.onPermissionResult(granted)
        }

        setContent {
            val saveableStateHolder = rememberSaveableStateHolder()
            saveableStateHolder.SaveableStateProvider(true) {
                PresentationRootView(ComposeContext())
                SideEffect { saveableStateHolder.removeState(true) }
            }
        }

        AppDelegate.shared.onLaunch()

        // Example of requesting permissions on startup.
        // These must match the permissions in the AndroidManifest.xml file.
        //let permissions = listOf(
        //    Manifest.permission.ACCESS_COARSE_LOCATION,
        //    Manifest.permission.ACCESS_FINE_LOCATION
        //    Manifest.permission.CAMERA,
        //    Manifest.permission.WRITE_EXTERNAL_STORAGE,
        //)
        //let requestTag = 1
        //ActivityCompat.requestPermissions(self, permissions.toTypedArray(), requestTag)
    }

    override fun onStart() {
        logger.info("onStart")
        super.onStart()
    }

    override fun onResume() {
        super.onResume()
        AppDelegate.shared.onResume()
    }

    override fun onPause() {
        super.onPause()
        AppDelegate.shared.onPause()
    }

    override fun onStop() {
        super.onStop()
        AppDelegate.shared.onStop()
    }

    override fun onDestroy() {
        super.onDestroy()
        AppDelegate.shared.onDestroy()
    }

    override fun onLowMemory() {
        super.onLowMemory()
        AppDelegate.shared.onLowMemory()
    }

    override fun onRestart() {
        logger.info("onRestart")
        super.onRestart()
    }

    override fun onSaveInstanceState(outState: android.os.Bundle): Unit = super.onSaveInstanceState(outState)

    override fun onRestoreInstanceState(bundle: android.os.Bundle) {
        // Usually you restore your state in onCreate(). It is possible to restore it in onRestoreInstanceState() as well, but not very common. (onRestoreInstanceState() is called after onStart(), whereas onCreate() is called before onStart().
        logger.info("onRestoreInstanceState")
        super.onRestoreInstanceState(bundle)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: kotlin.Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        logger.info("onRequestPermissionsResult: ${requestCode}")
    }

    companion object {
    }
}

@Composable
internal fun SyncSystemBarsWithTheme() {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f

    val transparent = AndroidColor.TRANSPARENT
    val style = if (dark) {
        SystemBarStyle.dark(transparent)
    } else {
        SystemBarStyle.light(transparent, transparent)
    }

    val activity = LocalContext.current as? ComponentActivity
    DisposableEffect(style) {
        activity?.enableEdgeToEdge(
            statusBarStyle = style,
            navigationBarStyle = style
        )
        onDispose { }
    }
}

/// Theme.background (SharedUI/Theme.swift:20, #EFEFF1) — Drift's page grey.
private val DriftPageBackground = androidx.compose.ui.graphics.Color(0xFFEFEFF1)

@Composable
internal fun PresentationRootView(context: ComposeContext) {
    // Light-only (see AndroidAppMain.onCreate). Hardcoded rather than derived from
    // isSystemInDarkTheme() so the Compose scheme can't disagree with the process.
    val colorScheme = ColorScheme.light
    Material3ColorScheme({ scheme, _ ->
        // SkipUI paints every presentation root — including the strip between the
        // content and the floating pill bar — with colorScheme.surface
        // (skip-ui Color.swift:202 → PresentationRoot.swift:55). Material You
        // derives that from the wallpaper on API 31+, so the strip came out pale
        // lavender in light mode and near-black in dark. Pin surface+background
        // to the page grey so the strip matches the page in both. Scope stays
        // minimal — dialog/menu/sheet container tones are #1204's territory.
        scheme.copy(surface = DriftPageBackground, background = DriftPageBackground)
    }, content = {
        PresentationRoot(defaultColorScheme = colorScheme, context = context) { ctx ->
            SyncSystemBarsWithTheme()
            val contentContext = ctx.content()
            // #1180: register this scope as a reader of ComposeKick.rootTick, so
            // ComposeKick.kick() can invalidate the composition root and re-execute
            // the bridged tree. NOT wrapped in key(...) — key would recreate
            // composition state on every kick, losing scroll positions and the
            // focused text field; a plain read invalidates while keeping identity.
            ComposeKick.rootTick.value
            Box(modifier = ctx.modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                AppRootView().Compose(context = contentContext)
            }
        }
    })
}
