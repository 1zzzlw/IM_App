package com.example.im_app

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/** 在后台线程提取首帧，结果为 JPEG 字节，仅用于 HTTP 上传。 */
class MediaPreviewBridge(messenger: BinaryMessenger) {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "im_app/media_preview").setMethodCallHandler { call, result ->
            if (call.method != "videoThumbnail") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("preview", "视频路径为空", null)
                return@setMethodCallHandler
            }
            executor.execute {
                val retriever = MediaMetadataRetriever()
                var frame: Bitmap? = null
                var scaled: Bitmap? = null
                try {
                    retriever.setDataSource(path)
                    val source = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        ?: throw IllegalStateException("无法读取视频首帧")
                    frame = source
                    val ratio = minOf(1.0, 320.0 / max(source.width, source.height))
                    val thumbnail = Bitmap.createScaledBitmap(source,
                        max(1, (source.width * ratio).roundToInt()),
                        max(1, (source.height * ratio).roundToInt()), true)
                    scaled = thumbnail
                    val output = ByteArrayOutputStream()
                    if (!thumbnail.compress(Bitmap.CompressFormat.JPEG, 75, output)) {
                        throw IllegalStateException("视频封面编码失败")
                    }
                    val bytes = output.toByteArray()
                    main.post { result.success(bytes) }
                } catch (error: Exception) {
                    main.post { result.error("preview", error.message, null) }
                } finally {
                    if (scaled !== frame) scaled?.recycle()
                    frame?.recycle()
                    retriever.release()
                }
            }
        }
    }
}
