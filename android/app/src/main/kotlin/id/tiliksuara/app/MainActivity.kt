package id.tiliksuara.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.os.Environment
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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

                    "openFile" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mime") ?: "*/*"
                        if (path == null) {
                            result.error("NOT_FOUND", "Berkas tidak ditemukan", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            if (!file.isFile) {
                                result.error("NOT_FOUND", "Berkas tidak ditemukan", null)
                                return@setMethodCallHandler
                            }
                            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                            val intent =
                                Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, mime)
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            result.error("NO_APP", "Tidak ada aplikasi pembuka", null)
                        } catch (e: IllegalArgumentException) {
                            result.error("INVALID_FILE", "Berkas tidak dapat dibuka", null)
                        } catch (e: SecurityException) {
                            result.error("ACCESS_DENIED", "Berkas tidak dapat dibuka", null)
                        }
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }
}
