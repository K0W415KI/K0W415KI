package com.wifimapper.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.wifimapper.app.ui.App
import com.wifimapper.app.ui.WifiMapperTheme
import org.osmdroid.config.Configuration

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // OpenStreetMap exige que cada app se identifique al pedir los mapas.
        Configuration.getInstance().apply {
            load(applicationContext, getSharedPreferences("osmdroid", MODE_PRIVATE))
            userAgentValue = packageName
        }
        enableEdgeToEdge()
        setContent {
            WifiMapperTheme {
                App()
            }
        }
    }
}
