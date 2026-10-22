package com.example.testflutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    private var faceVault: FaceVaultChannel? = null
    private var sface: SFaceChannel? = null
    private var locationChannel: LocationChannel? = null
    private var capturePrivacy: MethodChannel? = null
    private var privateCaptureRoutes = 0
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        faceVault = FaceVaultChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        sface = SFaceChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        locationChannel = LocationChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger) { this }
        capturePrivacy = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nubibill/face_capture_privacy").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        privateCaptureRoutes++
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "close" -> {
                        privateCaptureRoutes = maxOf(0, privateCaptureRoutes - 1)
                        if (privateCaptureRoutes == 0) window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        locationChannel?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        faceVault?.close()
        faceVault = null
        sface?.close()
        sface = null
        locationChannel?.close()
        locationChannel = null
        capturePrivacy?.setMethodCallHandler(null)
        capturePrivacy = null
        privateCaptureRoutes = 0
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
