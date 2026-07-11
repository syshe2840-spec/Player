package com.vezoo.player

import android.app.Application

class VezooApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // initialize ProcessLifecycleOwner برای extractor/WorkManager
        androidx.lifecycle.ProcessLifecycleOwner.get()
    }
}
