package app.minireel.minireel

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "minireel/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(false)
                    else -> result.notImplemented()
                }
            }
    }
}
