package nl.onsmoment.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var kioskChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        kioskChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nl.onsmoment.kiosk"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startKiosk" -> { startLockTask(); result.success(null) }
                    "stopKiosk"  -> { stopLockTask();  result.success(null) }
                    else         -> result.notImplemented()
                }
            }
        }
    }

    // Geroepen door Android als de gebruiker het unpin-gebaar gebruikt.
    // Notificeert Flutter zodat TabletScherm kan beslissen of herpin nodig is.
    override fun onTaskUnpinned() {
        super.onTaskUnpinned()
        kioskChannel?.invokeMethod("onTaskUnpinned", null)
    }
}
