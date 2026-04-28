package com.flipero.parking_buddy

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "parking_buddy/config"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMapsApiKey" -> {
                        try {
                            val ai = packageManager.getApplicationInfo(
                                packageName,
                                PackageManager.GET_META_DATA
                            )
                            val key = ai.metaData?.getString("com.google.android.geo.API_KEY")
                            result.success(key)
                        } catch (e: PackageManager.NameNotFoundException) {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
