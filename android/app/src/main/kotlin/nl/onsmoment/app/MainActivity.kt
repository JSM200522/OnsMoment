package nl.onsmoment.app

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
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
                    "isBatteryOptimizationUit" -> {
                        // Pre-Marshmallow (API 22): battery-opt bestaat niet, altijd true.
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                            result.success(true)
                        } else {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        }
                    }
                    "vraagBatteryOptimizationUit" -> {
                        // Directe prompt via ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                        // vraagt toestemming zonder de gebruiker in de settings te dumpen.
                        // Fallback naar ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS als
                        // het direct-intent geblokkeerd is (sommige OEM's).
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            } catch (_: Exception) {
                                try {
                                    val fallback = Intent(
                                        Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(fallback)
                                } catch (_: Exception) {
                                    // Geen enkele intent beschikbaar — geef stil op;
                                    // de Dart-kant handelt UI-melding zelf af.
                                }
                            }
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
