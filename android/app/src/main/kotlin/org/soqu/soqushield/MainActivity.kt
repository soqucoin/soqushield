package org.soqu.soqushield

import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity required for local_auth biometric prompts
// and flutter_secure_storage EncryptedSharedPreferences.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // SECURITY: Prevent screenshots, screen recording, and app switcher
        // preview. Protects seed phrases, balances, and addresses from
        // capture by other apps or the Android recent apps view.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The store screenshots come from the device drive on an emulator,
        // which needs the flag lifted. Only a debuggable build lifts it: a
        // release build answers false and keeps the flag whatever the caller
        // says. The call lives in integration_test/, never in lib/.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAPTURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "allowCapture") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val debuggable =
                    (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                if (debuggable) {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(debuggable)
            }
    }

    companion object {
        private const val CAPTURE_CHANNEL = "org.soqu.soqushield/capture"
    }
}
