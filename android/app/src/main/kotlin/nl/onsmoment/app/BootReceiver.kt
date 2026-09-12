package nl.onsmoment.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Ontvangt BOOT_COMPLETED en start de app opnieuw als de tablet in de
 * vergrendelde rustige modus stond (weergaveModus == 'vergrendeld' of null).
 *
 * Android 10+ verbiedt het direct starten van een Activity vanuit een
 * BroadcastReceiver. Oplossing: een high-priority fullScreenIntent-notificatie
 * die het scherm wekt en de app opent zodra de verzorger of eigenaar de tablet
 * aanraakt na de herstart.
 *
 * SharedPreferences-sleutel: Flutter slaat weergaveModus op met prefix
 * "flutter." in het bestand "FlutterSharedPreferences".
 *
 * Samsung/Xiaomi: autostart moet handmatig ingeschakeld worden in de
 * fabrikant-specifieke accu/autostart-instellingen. Zonder dat vuurde
 * deze receiver niet na een herstart. Setup-instructie tonen bij kiosk-
 * activatie is een toekomstig verbeterpunt (zie CLAUDE.md openstaand).
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val modus = prefs.getString("flutter.ons_moment_weergave_modus", null)
        // null = backwards compat, geen weergaveModus → ook vergrendeld
        val moetStarten = (modus == "vergrendeld" || modus == null)
        if (!moetStarten) return

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) ?: return

        // C-1 (12 sept 2026): als SYSTEM_ALERT_WINDOW-toestemming
        // ("Weergeven over andere apps") is verleend, biedt Android een
        // BAL-exemption (Background Activity Start) waarmee we
        // MainActivity direct kunnen starten — géén tik meer nodig na
        // reboot. Zelfde pattern als OnsMomentFcmReceiver bij auto-
        // answer. Wanneer verleend: de rustige-modus-tablet komt na
        // stroomuitval vanzelf terug in Ons Moment.
        //
        // Zonder de toestemming: val terug op de bestaande fullScreen-
        // Intent-notif (vereist een tik). Fail-safe — nul regressie voor
        // installaties zonder deze toestemming.
        if (canDrawOverlaysNow(context)) {
            try {
                context.startActivity(launchIntent)
                Log.i(
                    "OMBoot",
                    "BOOT_COMPLETED → MainActivity gestart via BAL-exemption " +
                            "(SYSTEM_ALERT_WINDOW). Rustige modus komt vanzelf terug."
                )
                return
            } catch (e: Exception) {
                Log.w(
                    "OMBoot",
                    "BOOT_COMPLETED startActivity faalde ondanks overlay-toestemming: " +
                            "${e.message} — val terug op fullScreenIntent-notif."
                )
                // Doorval naar de notif-fallback hieronder.
            }
        } else {
            Log.d(
                "OMBoot",
                "BOOT_COMPLETED zonder overlay-toestemming — toon " +
                        "fullScreenIntent-notif (gebruiker moet tikken)."
            )
        }

        val pi = PendingIntent.getActivity(
            context, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val channelId = "ons_moment_boot"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                channelId,
                "Ons Moment herstart",
                NotificationManager.IMPORTANCE_HIGH
            )
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(ch)
        }

        val notif = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_ons_moment)
            .setContentTitle("Ons Moment")
            .setContentText("Tik hier om Ons Moment opnieuw te openen.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setFullScreenIntent(pi, true)
            .setAutoCancel(true)
            .build()

        NotificationManagerCompat.from(context).notify(9001, notif)
    }

    private fun canDrawOverlaysNow(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                Settings.canDrawOverlays(context)
            } catch (_: Exception) {
                false
            }
        } else true
    }
}
