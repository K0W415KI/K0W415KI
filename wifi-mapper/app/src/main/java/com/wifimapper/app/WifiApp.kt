package com.wifimapper.app

import android.app.Application
import com.wifimapper.app.data.CalibrationStore

class WifiApp : Application() {
    override fun onCreate() {
        super.onCreate()
        CalibrationStore.load(this)
    }
}
