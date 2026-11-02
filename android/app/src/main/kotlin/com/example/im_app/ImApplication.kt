package com.example.im_app

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

class ImApplication : Application() {
    lateinit var bridge: MobileBridge
    // 引擎由 Application 持有，移除界面任务时不销毁正在收消息的 Dart 连接。
    val chatEngine: FlutterEngine by lazy {
        FlutterEngine(this).also {
            bridge = MobileBridge(this, it.dartExecutor.binaryMessenger)
            it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
    }
}
