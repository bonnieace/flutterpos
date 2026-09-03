package com.example.flutter_application_1

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The activity, plus the one thing Dart cannot read for itself.
 *
 * **Why a channel exists at all.** The till's device identity used to be a
 * random value minted on first launch and kept in an encrypted box inside the
 * app's own data. Uninstalling the app - or any wipe of app data - destroyed it,
 * so the same physical till came back as a stranger and a shift it had left open
 * was reported as "open on another device" with no other device to go and close
 * it on. `Settings.Secure.ANDROID_ID` survives that: it is scoped to this
 * device, this Android user, and this signing key, and it outlives an uninstall.
 *
 * It is never sent anywhere. Dart hashes it before it is stored or printed, so
 * what leaves this method lives only long enough to become a digest.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_IDENTITY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                HARDWARE_ID_METHOD -> result.success(hardwareId())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * The durable device value, or null when this device has none worth having.
     *
     * Null is a supported answer, not a failure: Dart falls back to the random
     * identity it has always minted, which costs exactly what the old behaviour
     * cost. Returning something unusable would be worse, so the two known-bad
     * answers are filtered - a blank value, and the buggy constant that a batch
     * of early devices all reported as their own.
     */
    private fun hardwareId(): String? {
        val value = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        if (value.isNullOrBlank() || value == KNOWN_DUPLICATED_ANDROID_ID) return null
        return value
    }

    private companion object {
        const val DEVICE_IDENTITY_CHANNEL = "pos/device-identity"
        const val HARDWARE_ID_METHOD = "hardwareId"
        const val KNOWN_DUPLICATED_ANDROID_ID = "9774d56d682e549c"
    }
}
