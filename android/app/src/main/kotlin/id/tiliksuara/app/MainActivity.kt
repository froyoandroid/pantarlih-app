package id.tiliksuara.app

import android.os.Build
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "id.tiliksuara.app/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdkVersion" -> {
                        result.success(Build.VERSION.SDK_INT)
                    }

                    "documentsPath" -> {
                        result.success(
                            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS).absolutePath,
                        )
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }
}
