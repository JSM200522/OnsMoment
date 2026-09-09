package nl.onsmoment.app

import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var kioskChannel: MethodChannel? = null
    private var kioskActief = false

    // BEL-D1: gecacht auto-answer payload uit OnsMomentFcmReceiver-intent.
    // Wordt gezet zodra de Activity opent via het BAL-exempted
    // startActivity-pad (scherm AAN + app dicht + overlay-toestemming).
    // Dart's main-isolate leest 'm via de "haalPendingAutoAnswer"
    // MethodChannel-call op RouterScherm-init en publiceert 'm dan naar
    // incomingCallNotifier zodat _verwerkInkomendGesprek de auto-answer
    // waarschuwing + GesprekScherm-flow start.
    private var pendingAutoAnswerPayload: String? = null
    private var pendingAutoAnswerCallId: String? = null

    // BEL-S10: als de app door een inkomend_gesprek-melding wordt
    // gelaunched (body-tap OF fullScreenIntent-auto-launch bij scherm-
    // UIT), zet dan CONDITIONEEL de show-when-locked + turn-screen-on
    // flags zodat InkomendGesprekScherm zichtbaar rinkelend BOVEN het
    // keyguard verschijnt en het scherm wordt gewekt. Zonder deze
    // flags start Android de Activity wél maar blijft ze achter het
    // slot; scherm blijft uit — de tester zag daardoor "niets", en
    // pas bij handmatig ontgrendelen zat hij ineens in de app.
    // Detectie via het "payload"-intent-extra dat flutter_local_
    // notifications meestuurt bij tap/launch.
    private val plugintagBelLaunch = "OMBelS10"

    // BEL-S10: cold-start pad — flag zetten vóór de Activity zichtbaar
    // wordt. onCreate wordt door FlutterActivity aangeroepen; wij hooken
    // hier meteen op zodat setShowWhenLocked/setTurnScreenOn effect
    // hebben bij de eerste render.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleInkomendGesprekLaunch(intent, bron = "onCreate")
    }

    // BEL-S10: warm-start pad — app draaide al en krijgt een nieuw
    // launch-intent (bijv. body-tap terwijl app op achtergrond staat).
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleInkomendGesprekLaunch(intent, bron = "onNewIntent")
    }

    private fun handleInkomendGesprekLaunch(intent: Intent?, bron: String) {
        if (intent == null) {
            Log.d(plugintagBelLaunch, "handle($bron): intent=null, skip")
            return
        }
        val payload = intent.getStringExtra("payload")
        if (payload.isNullOrEmpty()) {
            Log.d(plugintagBelLaunch, "handle($bron): geen payload, skip")
            return
        }
        // BEL-D1: cache payload + callId als deze launch komt van de
        // OnsMomentFcmReceiver-auto-answer-flow. Dart leest ze op via
        // "haalPendingAutoAnswer" en start de auto-answer-UX.
        if (intent.getBooleanExtra(
                OnsMomentFcmReceiver.EXTRA_AUTO_ANSWER_FROM_FCM, false)) {
            pendingAutoAnswerPayload = payload
            pendingAutoAnswerCallId =
                intent.getStringExtra(OnsMomentFcmReceiver.EXTRA_AUTO_ANSWER_CALL_ID)
            Log.i(plugintagBelLaunch,
                "handle($bron): auto-answer-launch gecached " +
                    "(callId=$pendingAutoAnswerCallId)")
        }
        // Payload is JSON-string van _toonGesprekNotificatie. Kijken naar
        // de type-string zonder volledig te parsen (zou een JSON-lib nodig
        // hebben; naive contains volstaat en is snel).
        if (!payload.contains("\"type\":\"inkomend_gesprek\"")) {
            Log.d(plugintagBelLaunch, "handle($bron): payload geen bel, skip")
            return
        }
        Log.i(plugintagBelLaunch,
            "handle($bron): inkomend_gesprek launch → showWhenLocked + " +
                "turnScreenOn + requestDismissKeyguard")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            try {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            } catch (e: Exception) {
                Log.w(plugintagBelLaunch,
                    "setShowWhenLocked/turnScreenOn faalde: ${e.message}")
            }
        }
        try {
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (km.isKeyguardLocked) {
                km.requestDismissKeyguard(this, null)
                Log.i(plugintagBelLaunch, "requestDismissKeyguard verzonden")
            }
        } catch (e: Exception) {
            Log.w(plugintagBelLaunch,
                "requestDismissKeyguard faalde: ${e.message}")
        }
    }

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
                    // BEL-C6 (DEEL A): SYSTEM_ALERT_WINDOW-check zodat de
                    // Dart-kant weet of we auto-answer bij scherm-aan + app
                    // dicht kunnen forceren (background-activity-start via
                    // BAL-exemption). Pre-Marshmallow bestaat de check niet
                    // — dan altijd true (de permission is er 'gratis').
                    "canDrawOverlays" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            result.success(Settings.canDrawOverlays(this))
                        } else {
                            result.success(true)
                        }
                    }
                    // BEL-D1: Dart leest hier de FCM-payload uit als de
                    // Activity zojuist door OnsMomentFcmReceiver is gestart
                    // vanwege een auto-answer-scenario. Returnt null als
                    // er geen pending payload is (normale launch).
                    "haalPendingAutoAnswer" -> {
                        val payload = pendingAutoAnswerPayload
                        val callId = pendingAutoAnswerCallId
                        // Éénmalig — na deze read wist Dart de state.
                        pendingAutoAnswerPayload = null
                        pendingAutoAnswerCallId = null
                        if (payload == null) {
                            result.success(null)
                        } else {
                            result.success(mapOf(
                                "payload" to payload,
                                "callId" to (callId ?: "")
                            ))
                        }
                    }
                    // Opent de special-access-settings-pagina voor
                    // "Weergeven over andere apps". Geen directe prompt-
                    // dialog beschikbaar (Android-limitatie) — de gebruiker
                    // ziet Ons Moment in de lijst en tikt de toggle.
                    "vraagOverlayToestemming" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            } catch (_: Exception) {
                                // Op enkele OEMs is de intent afgeschermd —
                                // val stil terug, de Dart-kant toont zelf UI.
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
