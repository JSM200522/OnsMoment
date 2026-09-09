package nl.onsmoment.app

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

/**
 * Parallel-BroadcastReceiver op `com.google.android.c2dm.intent.RECEIVE`
 * naast de FCM-plugin (FlutterFirebaseMessagingReceiver).
 *
 * Doel — AUTO-ANSWER bij scherm-AAN en app-DICHT/killed.
 *
 * Android's fullScreenIntent-mechanisme auto-launcht een Activity ALLEEN
 * bij scherm UIT / lockscreen; bij scherm AAN degradeert het naar heads-up
 * en de gebruiker moet tikken. Voor een dementie-vriendelijke auto-answer
 * moet dat óók bij scherm-aan werken.
 *
 * Enige weg (Android 10+): expliciete `startActivity()` vanuit een
 * BroadcastReceiver, met FLAG_ACTIVITY_NEW_TASK, ONDER voorwaarde dat
 * de app een BAL-exemption (Background Activity Start) heeft. De
 * SYSTEM_ALERT_WINDOW-permission ("Weergeven over andere apps") is
 * hiervoor de geldige exemption — daarom vragen we hem alleen aan zodra
 * de kring-eigenaar `autoAnswer=true` aanzet.
 *
 * Zonder toestemming, of bij een fout: dit receiver doet NIETS behalve
 * loggen. De normale FCM-plugin-flow blijft dan verantwoordelijk voor
 * de fullScreenIntent-notif (die dekt scherm-uit + biedt tap-om-op-te-
 * nemen bij scherm-aan). Nul regressierisico voor de bestaande paden.
 *
 * Belangrijke ontwerp-keuzes:
 * - We interfereren NIET met het plugin-receiver: beide firen parallel
 *   voor dezelfde broadcast. De Dart-achtergrond-handler blijft draaien.
 * - Als de auto-answer route slaagt schrijven we een "skip_notif"-vlag
 *   naar SharedPreferences zodat de Dart-handler zijn eigen heads-up
 *   overslaat en er geen dubbele UX ontstaat.
 * - Alle diagnose-velden gaan naar `FlutterSharedPreferences` zodat het
 *   Dart bel-log ze kan lezen zonder MethodChannel-plumbing over
 *   isolate-grenzen.
 *
 * Platform-principe (CLAUDE.md): dit is Android-specifiek. iOS lost auto-
 * answer op via PushKit + CallKit (FASE G) — er blijft geen aanroep vanuit
 * platform-neutrale Dart-code naar deze receiver, dus iOS wordt niet
 * geraakt.
 */
class OnsMomentFcmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        try {
            val extras = intent.extras ?: return
            val remoteMessage = RemoteMessage(extras)
            val data = remoteMessage.data
            val type = data["type"] ?: return
            if (type != "inkomend_gesprek") return

            val autoAnswer = data["autoAnswer"] == "true"
            val callId = data["callId"] ?: ""
            val overlayOk = canDrawOverlaysNow(context)
            val screenOn = isScreenInteractive(context)
            val locked = isKeyguardLocked(context)

            persistDiag(
                context,
                callId = callId,
                type = type,
                autoAnswer = autoAnswer,
                screenOn = screenOn,
                locked = locked,
                overlayOk = overlayOk,
            )
            Log.i(TAG,
                "FCM inkomend_gesprek ontvangen — callId=$callId " +
                        "autoAnswer=$autoAnswer screenOn=$screenOn " +
                        "locked=$locked overlayOk=$overlayOk"
            )

            // Alleen forceren als ALLE voorwaarden matchen. Anders laten
            // we de standaard-flow (fullScreenIntent-notif) volledig zijn
            // werk doen — dat is het bewezen pad voor scherm-uit én voor
            // handmatig tikken bij scherm-aan.
            if (!autoAnswer) {
                Log.d(TAG, "skip auto-launch: autoAnswer=false")
                return
            }
            if (!overlayOk) {
                Log.d(TAG, "skip auto-launch: geen overlay-toestemming " +
                        "(SYSTEM_ALERT_WINDOW); val terug op FSI-notif")
                return
            }
            if (!screenOn) {
                Log.d(TAG, "skip auto-launch: scherm UIT — fullScreenIntent " +
                        "van de plugin-notif regelt dit al betrouwbaar")
                return
            }

            // Match: bouw MainActivity-intent met FCM-payload en start.
            // BAL-exemption via SYSTEM_ALERT_WINDOW maakt deze background-
            // activity-start toegestaan op API 29+.
            val payload = jsonFromData(data)
            val callIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
                putExtra("payload", payload)
                putExtra(EXTRA_AUTO_ANSWER_FROM_FCM, true)
                putExtra(EXTRA_AUTO_ANSWER_CALL_ID, callId)
            }
            try {
                context.startActivity(callIntent)
                // Vlag zodat de Dart bg-handler zijn eigen heads-up overslaat.
                markeerAutoAnswerGestart(context, callId)
                Log.i(TAG,
                    "AUTO-ANSWER startActivity OK (BAL-exemption via " +
                            "SYSTEM_ALERT_WINDOW) — Dart-notif wordt " +
                            "overgeslagen voor callId=$callId"
                )
            } catch (e: Exception) {
                Log.w(TAG, "AUTO-ANSWER startActivity FAALDE: ${e.message}")
                // Geen skip-flag zetten → Dart bg-handler toont normale notif.
            }
        } catch (e: Exception) {
            // Nooit doorspuwen naar de FCM-plugin — we mogen de normale
            // flow niet blokkeren.
            Log.e(TAG, "OnsMomentFcmReceiver crash: ${e.message}", e)
        }
    }

    private fun canDrawOverlaysNow(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try { Settings.canDrawOverlays(context) } catch (_: Exception) { false }
        } else true
    }

    private fun isScreenInteractive(context: Context): Boolean {
        return try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isInteractive
        } catch (_: Exception) { false }
    }

    private fun isKeyguardLocked(context: Context): Boolean {
        return try {
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            km.isKeyguardLocked
        } catch (_: Exception) { false }
    }

    private fun jsonFromData(data: Map<String, String>): String {
        val obj = JSONObject()
        for ((k, v) in data) obj.put(k, v)
        return obj.toString()
    }

    private fun persistDiag(
        context: Context,
        callId: String,
        type: String,
        autoAnswer: Boolean,
        screenOn: Boolean,
        locked: Boolean,
        overlayOk: Boolean,
    ) {
        try {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            prefs.edit()
                .putString("flutter.bel_diag_laatste_type", type)
                .putBoolean("flutter.bel_diag_auto_answer", autoAnswer)
                .putBoolean("flutter.bel_diag_screen_on", screenOn)
                .putBoolean("flutter.bel_diag_locked", locked)
                .putBoolean("flutter.bel_diag_overlay_ok", overlayOk)
                .putString("flutter.bel_diag_call_id", callId)
                .putLong("flutter.bel_diag_ts_ms", System.currentTimeMillis())
                .apply()
        } catch (_: Exception) {}
    }

    private fun markeerAutoAnswerGestart(context: Context, callId: String) {
        if (callId.isEmpty()) return
        try {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            prefs.edit()
                .putString("flutter.bel_auto_answer_gestart_call_id", callId)
                .putLong("flutter.bel_auto_answer_gestart_ts_ms",
                    System.currentTimeMillis())
                .apply()
        } catch (_: Exception) {}
    }

    companion object {
        private const val TAG = "OMBelAuto"
        const val EXTRA_AUTO_ANSWER_FROM_FCM = "nl.onsmoment.autoAnswerFromFcm"
        const val EXTRA_AUTO_ANSWER_CALL_ID = "nl.onsmoment.autoAnswerCallId"
    }
}
