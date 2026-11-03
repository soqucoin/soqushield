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
        // SECURITY: start PROTECTED, always. FLAG_SECURE blocks screenshots,
        // screen recording, casting and the recents preview.
        //
        // The owner can lift it in Settings (some people want to share a
        // balance or a receive code), and Dart re-applies that choice shortly
        // after launch via setAllowed. Until it does, the window is protected:
        // the first frames after a cold start are the ones most likely to show
        // a balance, and a default of "allowed" would expose them to anything
        // already recording.
        setSecure(true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAPTURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // The owner's Settings choice. Applied at launch and on
                    // every change; the seed screens override it while they
                    // are visible (ScreenCapture.whileProtected).
                    "setAllowed" -> {
                        val allow = call.argument<Boolean>("allow") ?: false
                        runOnUiThread { setSecure(!allow) }
                        result.success(true)
                    }

                    // The store screenshots come from the device drive on an
                    // emulator, which needs the flag lifted. Only a debuggable
                    // build lifts it: a release build answers false and keeps
                    // the flag whatever the caller says. The call lives in
                    // integration_test/, never in lib/.
                    "allowCapture" -> {
                        val debuggable =
                            (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                        if (debuggable) runOnUiThread { setSecure(false) }
                        result.success(debuggable)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun setSecure(secure: Boolean) {
        if (secure) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    companion object {
        private const val CAPTURE_CHANNEL = "org.soqu.soqushield/capture"
    }
}
