package nl.onsmoment.app

import android.app.ActivityManager
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

    // BEL-R2: launch-intent-lees voor callkit-accept.
    // Als de app door een 'Opnemen'-tik in de callkit-melding wordt geopend,
    // stuurt de plugin (via TransparentActivity → AppUtils.getAppIntent) een
    // launch-intent naar deze MainActivity met action
    // "${packageName}.com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"
    // en een bundle EXTRA_CALLKIT_CALL_DATA waarin o.a. EXTRA_CALLKIT_EXTRA
    // (HashMap) zit met daarin "fcmDataJson" (de originele FCM-payload die
    // we bij showCallkit meegaven).
    //
    // Reden voor deze workaround i.p.v. de plugin's onEvent-stream:
    // v2.5.0 bewaart geen betrouwbare state cross-process, dus bij
    // cold-start uit killed state gaat het accept-event verloren. De
    // launch-intent is echter een gewoon Android-intent en dus wél
    // beschikbaar bij zowel warm-start (onNewIntent) als cold-start
    // (onCreate → getIntent()).
    private var callkitLaunchChannel: MethodChannel? = null
    private var pendingAcceptFcmDataJson: String? = null
    private val plugintagCallkit = "OMBelR2"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // BEL-R2: registreer launch-channel meteen zodat Dart-kant vlak na
        // runApp() kan pollen (`getLaunchAcceptData`) en tegelijk een live
        // callback ontvangt bij warm-start-accepts (`onAcceptFromIntent`).
        callkitLaunchChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nl.onsmoment.callkit_launch"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchAcceptData" -> {
                        // Eenmalig consumeren — verhindert dat een tweede
                        // Dart-lookup dezelfde accept-data opnieuw triggert.
                        val data = pendingAcceptFcmDataJson
                        pendingAcceptFcmDataJson = null
                        Log.d(plugintagCallkit,
                            "getLaunchAcceptData → " +
                                if (data == null) "null (geen pending accept)"
                                else "STRING(len=${data.length})")
                        result.success(data)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Cold-start-pad: als de app werd opgestart doordat de gebruiker
        // 'Opnemen' tikte, bevat het initiële intent al de accept-data.
        parseerCallkitAcceptIntent(intent, "onCreate")

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

    // BEL-R2: warm-start-pad. Als de app al draaide (bijv. minimized) en de
    // gebruiker tikt 'Opnemen', komt hier een nieuw intent binnen zonder dat
    // onCreate opnieuw draait. We parsen en pushen direct naar Dart via het
    // callback-mechanisme; `getLaunchAcceptData` blijft ook werken als
    // Dart net iets later pollt.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Sla het nieuwe intent op zodat getIntent() ook getransplanteerd is
        // — anders blijft getIntent() het oude cold-start-intent teruggeven.
        setIntent(intent)
        parseerCallkitAcceptIntent(intent, "onNewIntent")
    }

    /**
     * BEL-R2: kernparser. Onderzoekt of dit intent afkomstig is van de
     * callkit-plugin's ACCEPT-actie, en zo ja: extraheert `fcmDataJson`
     * uit het geneste bundle en levert het aan de Dart-kant. Fail-soft:
     * onbekend action of ontbrekende sleutels → skip, geen crash.
     *
     * Ook aan te roepen vanuit onNewIntent (warm-start) — geldt dan als
     * "gebruiker tikte Opnemen terwijl app al draaide". In beide gevallen
     * geldt: consumeren éénmalig. `pendingAcceptFcmDataJson` wordt gezet
     * zodat de eerste Dart-invoke van `getLaunchAcceptData` de data leest;
     * daarnaast invoken we `onAcceptFromIntent` op het channel voor de
     * warm-start-flow (Dart zit dan al te luisteren).
     */
    private fun parseerCallkitAcceptIntent(intent: Intent?, bron: String) {
        if (intent == null) {
            Log.d(plugintagCallkit, "parse($bron): intent=null, skip")
            return
        }
        val action = intent.action
        if (action == null) {
            Log.d(plugintagCallkit, "parse($bron): action=null, skip")
            return
        }
        // Plugin bouwt de action als "${packageName}.${ACTION_CALL_ACCEPT}"
        // (zie CallkitIncomingBroadcastReceiver.kt + TransparentActivity.kt
        // in flutter_callkit_incoming 2.5.x). Match op suffix zodat we
        // niet aan applicationId-drift vastzitten.
        val isAccept =
            action.endsWith("com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT")
        if (!isAccept) {
            Log.d(plugintagCallkit,
                "parse($bron): action='$action' is geen callkit-accept, skip")
            return
        }
        // EXTRA_CALLKIT_CALL_DATA — constante-waarde is letterlijk de string
        // "EXTRA_CALLKIT_CALL_DATA" (zie FlutterCallkitIncomingPlugin.kt:25).
        val dataBundle: Bundle? = intent.getBundleExtra("EXTRA_CALLKIT_CALL_DATA")
        if (dataBundle == null) {
            Log.w(plugintagCallkit,
                "parse($bron): action MATCH maar geen EXTRA_CALLKIT_CALL_DATA " +
                    "— call-payload verloren")
            return
        }
        // EXTRA_CALLKIT_EXTRA is een HashMap<String, Any> (Serializable).
        // `fcmDataJson` is de sleutel die BelCallkitService.showCallkit heeft
        // gezet met jsonEncode(fcmData) — waardoor we daar de originele
        // FCM-payload uit halen (kringId, callId, calleeToken, etc.).
        @Suppress("DEPRECATION")
        val extraSerialised = dataBundle.getSerializable("EXTRA_CALLKIT_EXTRA")
        val extraMap = extraSerialised as? HashMap<*, *>
        if (extraMap == null) {
            Log.w(plugintagCallkit,
                "parse($bron): EXTRA_CALLKIT_EXTRA is geen HashMap " +
                    "(type=${extraSerialised?.javaClass?.name})")
            return
        }
        val fcmDataJson = extraMap["fcmDataJson"] as? String
        if (fcmDataJson.isNullOrEmpty()) {
            Log.w(plugintagCallkit,
                "parse($bron): geen fcmDataJson in EXTRA_CALLKIT_EXTRA " +
                    "(keys=${extraMap.keys.joinToString()})")
            return
        }
        pendingAcceptFcmDataJson = fcmDataJson
        Log.i(plugintagCallkit,
            "parse($bron): ✅ callkit-accept gedetecteerd — fcmDataJson " +
                "gebufferd (len=${fcmDataJson.length})")
        // Warm-start: Dart hangt al aan het channel, push direct. Bij cold-
        // start is het channel er wel maar Dart heeft z'n handler nog niet
        // gehecht — dan werkt de pending-buffer + eerste Dart-invoke van
        // getLaunchAcceptData. Beide paden zijn dus gedekt.
        try {
            callkitLaunchChannel?.invokeMethod("onAcceptFromIntent", fcmDataJson)
        } catch (e: Exception) {
            Log.w(plugintagCallkit,
                "parse($bron): invokeMethod onAcceptFromIntent faalde " +
                    "(niet blocking): ${e.message}")
        }
    }
}
