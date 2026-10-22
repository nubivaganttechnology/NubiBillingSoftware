package com.example.testflutter

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/**
 * Native Android inference runner for OpenCV SFace ONNX model using ONNX Runtime.
 * Inputs: 112x112 RGB aligned face crop (NCHW float32 [1, 3, 112, 112]).
 * Outputs: 128-dimensional L2-normalized face embedding vector.
 */
class SFaceChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "nubibill/sface_recognition")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var env: OrtEnvironment? = null
    private var session: OrtSession? = null

    init {
        channel.setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    when (call.method) {
                        "isModelAvailable" -> {
                            val available = ensureSession()
                            main.post { result.success(available) }
                        }
                        "embed" -> {
                            val rgb = call.argument<ByteArray>("rgb")
                                ?: throw IllegalArgumentException("Missing rgb bytes")
                            val edge = call.argument<Int>("edge") ?: 112
                            require(rgb.size == edge * edge * 3) { "Invalid RGB size" }
                            ensureSession()
                            val vector = runInference(rgb, edge)
                            val list = vector.map { it.toDouble() }
                            main.post { result.success(list) }
                        }
                        else -> main.post { result.notImplemented() }
                    }
                } catch (e: Exception) {
                    main.post { result.error("SFACE_INFERENCE_ERROR", e.message, null) }
                }
            }
        }
    }

    private fun ensureSession(): Boolean {
        if (session != null) return true
        if (env == null) {
            env = OrtEnvironment.getEnvironment()
        }
        val modelFile = File(context.filesDir, "face_recognition_sface_2021dec.onnx")
        if (!modelFile.exists() || modelFile.length() < 30000000L) {
            val assetPath = "flutter_assets/assets/models/face_recognition_sface_2021dec.onnx"
            context.assets.open(assetPath).use { input ->
                FileOutputStream(modelFile).use { output ->
                    input.copyTo(output)
                }
            }
        }
        val opts = OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(2)
        }
        session = env!!.createSession(modelFile.absolutePath, opts)
        return true
    }

    private fun runInference(rgb: ByteArray, edge: Int): FloatArray {
        val ortEnv = env ?: throw IllegalStateException("Env not initialized")
        val sess = session ?: throw IllegalStateException("Session not initialized")

        // SFace expects NCHW float32 input: shape [1, 3, 112, 112]
        // Range: 0.0f .. 255.0f
        // Order: RGB
        val channelSize = edge * edge
        val floatBuffer = ByteBuffer.allocateDirect(1 * 3 * edge * edge * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()

        // Red plane
        for (i in 0 until channelSize) {
            val r = rgb[i * 3].toInt() and 0xFF
            floatBuffer.put(r.toFloat())
        }
        // Green plane
        for (i in 0 until channelSize) {
            val g = rgb[i * 3 + 1].toInt() and 0xFF
            floatBuffer.put(g.toFloat())
        }
        // Blue plane
        for (i in 0 until channelSize) {
            val b = rgb[i * 3 + 2].toInt() and 0xFF
            floatBuffer.put(b.toFloat())
        }
        floatBuffer.rewind()

        val inputShape = longArrayOf(1, 3, edge.toLong(), edge.toLong())
        val inputName = sess.inputNames.iterator().next()
        val tensor = OnnxTensor.createTensor(ortEnv, floatBuffer, inputShape)

        tensor.use { inTensor ->
            val output = sess.run(mapOf(inputName to inTensor))
            output.use { outMap ->
                val rawObj = outMap[0].value
                val rawFeature: FloatArray = when (rawObj) {
                    is Array<*> -> {
                        @Suppress("UNCHECKED_CAST")
                        (rawObj as Array<FloatArray>)[0]
                    }
                    is FloatArray -> rawObj
                    else -> throw IllegalStateException("Unexpected output tensor type: ${rawObj?.javaClass}")
                }
                // Normalize L2
                var norm = 0.0
                for (v in rawFeature) {
                    norm += (v * v).toDouble()
                }
                norm = Math.sqrt(norm)
                if (norm < 1e-12) norm = 1.0
                val normalized = FloatArray(rawFeature.size)
                for (i in rawFeature.indices) {
                    normalized[i] = (rawFeature[i] / norm).toFloat()
                }
                return normalized
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        worker.execute {
            session?.close()
            session = null
            env?.close()
            env = null
        }
        worker.shutdown()
    }
}
