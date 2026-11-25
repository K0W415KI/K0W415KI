package com.wifimapper.app.data

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiManager
import android.os.SystemClock
import androidx.core.content.ContextCompat
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch

data class ScannedNetwork(
    val bssid: String,
    val ssid: String,
    val rssi: Int,
    val frequency: Int,
    val capabilities: String,
)

class WifiScanner(context: Context) {
    private val appContext = context.applicationContext
    private val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    /**
     * Emite la lista de redes cada vez que el sistema termina un escaneo.
     * Android limita los escaneos pedidos por apps a 4 cada 2 minutos, por eso se pide
     * uno cada [SCAN_INTERVAL_MS]; también llegan los escaneos que dispara el propio sistema.
     * Requiere permiso de ubicación (y NEARBY_WIFI_DEVICES en Android 13+).
     */
    @SuppressLint("MissingPermission")
    fun scans(): Flow<List<ScannedNetwork>> = callbackFlow {
        fun emitResults() {
            val nowMicros = SystemClock.elapsedRealtime() * 1000
            val fresh = wifi.scanResults
                // Descarta resultados viejos: se asociarían a una posición GPS equivocada.
                .filter { it.BSSID != null && nowMicros - it.timestamp < MAX_RESULT_AGE_MICROS }
                .map {
                    @Suppress("DEPRECATION")
                    ScannedNetwork(it.BSSID, it.SSID.orEmpty(), it.level, it.frequency, it.capabilities.orEmpty())
                }
            trySend(fresh)
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) = emitResults()
        }
        ContextCompat.registerReceiver(
            appContext,
            receiver,
            IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )

        emitResults()
        launch {
            while (true) {
                @Suppress("DEPRECATION")
                wifi.startScan()
                delay(SCAN_INTERVAL_MS)
            }
        }

        awaitClose { appContext.unregisterReceiver(receiver) }
    }

    companion object {
        const val SCAN_INTERVAL_MS = 30_000L
        private const val MAX_RESULT_AGE_MICROS = 20_000_000L
    }
}
