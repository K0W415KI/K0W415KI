package com.wifimapper.app.data

import android.content.Context
import android.location.Location
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/** Un valor de señal en el tiempo, para el gráfico de historial. */
data class Reading(val timestamp: Long, val rssi: Int)

/**
 * Único dueño del bucle de escaneo (wifi + GPS). Lo comparten la pantalla y el servicio en
 * segundo plano: cada uno llama a [start]/[stop] y un contador de referencias mantiene un solo
 * bucle activo, así nunca se escanea dos veces en paralelo.
 */
object ScanEngine {
    const val HISTORY_CAP = 180

    val visible = MutableStateFlow<Map<String, Int>>(emptyMap())
    val location = MutableStateFlow<Location?>(null)
    val locationEnabled = MutableStateFlow(true)
    val history = MutableStateFlow<Map<String, List<Reading>>>(emptyMap())
    val scanning = MutableStateFlow(false)

    private var repo: Repository? = null
    private var scanner: WifiScanner? = null
    private var tracker: LocationTracker? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var job: Job? = null
    private var refs = 0

    @Synchronized
    private fun ensure(context: Context) {
        if (repo != null) return
        val app = context.applicationContext
        repo = Repository(AppDb.get(app).dao())
        scanner = WifiScanner(app)
        tracker = LocationTracker(app)
    }

    fun repository(context: Context): Repository {
        ensure(context)
        return repo!!
    }

    @Synchronized
    fun start(context: Context) {
        ensure(context)
        refs++
        if (job != null) return
        locationEnabled.value = tracker!!.isEnabled()
        scanning.value = true
        job = scope.launch {
            launch { tracker!!.updates().collect { location.value = it } }
            scanner!!.scans().collect { scan ->
                visible.value = scan.associate { it.bssid to it.rssi }
                appendHistory(scan)
                repo!!.onScan(scan, location.value)
                locationEnabled.value = tracker!!.isEnabled()
            }
        }
    }

    @Synchronized
    fun stop() {
        if (refs > 0) refs--
        if (refs == 0) {
            job?.cancel()
            job = null
            scanning.value = false
        }
    }

    private fun appendHistory(scan: List<ScannedNetwork>) {
        val now = System.currentTimeMillis()
        val updated = history.value.toMutableMap()
        for (net in scan) {
            val list = (updated[net.bssid] ?: emptyList()) + Reading(now, net.rssi)
            updated[net.bssid] = if (list.size > HISTORY_CAP) list.takeLast(HISTORY_CAP) else list
        }
        history.value = updated
    }
}
