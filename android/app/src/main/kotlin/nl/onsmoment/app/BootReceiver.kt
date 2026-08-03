package nl.onsmoment.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
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
}
