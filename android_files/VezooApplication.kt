package com.vezoo.player

import android.app.Application
import androidx.work.Configuration

class VezooApplication : Application(), Configuration.Provider {
    override fun onCreate() {
        super.onCreate()
    }

    override fun getWorkManagerConfiguration(): Configuration =
        Configuration.Builder()
            .setMinimumLoggingLevel(android.util.Log.ERROR)
            .build()
}
