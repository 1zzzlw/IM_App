package com.example.im_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Context
import android.content.Intent
import android.os.Bundle

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        (application as ImApplication).chatEngine

    override fun shouldDestroyEngineWithHost() = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        (application as ImApplication).bridge.apply {
            activity = this@MainActivity
            handleIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        (application as ImApplication).bridge.handleIntent(intent)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        (application as ImApplication).bridge.permissionResult(code)
    }

    override fun onDestroy() {
        (application as ImApplication).bridge.activity = null
        super.onDestroy()
    }
}
