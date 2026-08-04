package nl.onsmoment.app

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
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
                    "checkFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                            result.success(nm.canUseFullScreenIntent())
                        } else {
                            result.success(true)
                        }
                    }
                    "requestFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        }
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
