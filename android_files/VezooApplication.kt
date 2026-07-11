package com.vezoo.player

import android.app.Application
import androidx.lifecycle.ProcessLifecycleOwner

class VezooApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // force initialize lifecycle برای extractor package
        try {
            ProcessLifecycleOwner.get()
        } catch (_: Exception) {
            // ignore if already initialized
        }
    }
}

