package nl.onsmoment.app

import android.app.ActivityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var kioskChannel: MethodChannel? = null
    private var kioskActief = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        kioskChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nl.onsmoment.kiosk"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startKiosk" -> {
                        startLockTask()
                        kioskActief = true
                        result.success(null)
                    }
                    "stopKiosk" -> {
                        kioskActief = false
                        stopLockTask()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // onWindowFocusChanged bestaat in android.app.Activity sinds API 1.
    // We gebruiken het om te detecteren dat de gebruiker het unpin-gebaar
    // heeft gebruikt: focus keert terug (hasFocus=true) terwijl lockTaskModeState
    // NONE is, mits kioskActief=true zodat eigenaar-stopKiosk geen vals positief geeft.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || !kioskActief) return
        val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        if (am.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_NONE) {
            kioskActief = false
            kioskChannel?.invokeMethod("onTaskUnpinned", null)
        }
    }
}
