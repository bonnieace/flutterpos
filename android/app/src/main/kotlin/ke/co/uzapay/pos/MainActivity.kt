package ke.co.uzapay.pos

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The activity, plus the two things Dart cannot read for itself.
 *
 * **Why the device channel exists at all.** The till's device identity used to
 * be a random value minted on first launch and kept in an encrypted box inside
 * the app's own data. Uninstalling the app - or any wipe of app data - destroyed
 * it, so the same physical till came back as a stranger and a shift it had left
 * open was reported as "open on another device" with no other device to go and
 * close it on. `Settings.Secure.ANDROID_ID` survives that: it is scoped to this
 * device, this Android user, and this signing key, and it outlives an uninstall.
 *
 * It is never sent anywhere. Dart hashes it before it is stored or printed, so
 * what leaves this method lives only long enough to become a digest.
 *
 * **Why the link channel exists.** A staff invitation's URL carries the proof
 * that accepts it, and `Uri.base` on Android is a filesystem path - it has never
 * held a query string, so the app read `null` from it on every launch and no
 * emailed invitation could ever be acted on. The intent has the URL; this hands
 * it over, once for the launch and again for every later one.
 *
 * Deliberately not Flutter's own deep linking, which would put the URL in front
 * of the `Navigator` as a route name. This app has one route.
 */
class MainActivity : FlutterActivity() {
    /**
     * The launch URL, until Dart takes it.
     *
     * Held rather than pushed because the engine is configured before the Dart
     * entrypoint runs: a message sent now would be sent to nobody. Cleared on
     * being taken, so a configuration change that rebuilds the activity cannot
     * present the same invitation a second time.
     */
    private var pendingLink: String? = null
    private var linkChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingLink = viewedUrl(intent)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_IDENTITY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                HARDWARE_ID_METHOD -> result.success(hardwareId())
                else -> result.notImplemented()
            }
        }
        linkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LAUNCH_LINK_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    TAKE_LAUNCH_LINK_METHOD -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * A link followed while the app was already running.
     *
     * `singleTop` in the manifest is what routes it here rather than starting a
     * second activity, and Dart is listening by now, so this one is pushed. It
     * is still parked if the channel has gone - the engine can be detached while
     * the activity lives - and the next take collects it.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val url = viewedUrl(intent) ?: return
        val channel = linkChannel
        if (channel == null) {
            pendingLink = url
            return
        }
        channel.invokeMethod(LAUNCH_LINK_METHOD, url)
    }

    override fun onDestroy() {
        linkChannel?.setMethodCallHandler(null)
        linkChannel = null
        super.onDestroy()
    }

    /** The URL an `ACTION_VIEW` intent carries, or null for any other launch. */
    private fun viewedUrl(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        return intent.dataString
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
        const val LAUNCH_LINK_CHANNEL = "pos/launch-link"
        const val TAKE_LAUNCH_LINK_METHOD = "takeLaunchLink"
        const val LAUNCH_LINK_METHOD = "launchLink"
        const val KNOWN_DUPLICATED_ANDROID_ID = "9774d56d682e549c"
    }
}
