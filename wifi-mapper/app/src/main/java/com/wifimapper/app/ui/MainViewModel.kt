package com.wifimapper.app.ui

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.wifimapper.app.data.AppDb
import com.wifimapper.app.data.CalibrationStore
import com.wifimapper.app.data.NetworkEntity
import com.wifimapper.app.data.OrientationTracker
import com.wifimapper.app.data.Reading
import com.wifimapper.app.data.Repository
import com.wifimapper.app.data.SampleEntity
import com.wifimapper.app.data.ScanEngine
import com.wifimapper.app.data.ScanService
import com.wifimapper.app.domain.Calibration
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val repository: Repository = ScanEngine.repository(app)
    private val orientation = OrientationTracker(app)

    val networks: StateFlow<List<NetworkEntity>> =
        repository.networks.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    // Estado compartido con el servicio en segundo plano.
    val location = ScanEngine.location
    val visible = ScanEngine.visible
    val locationEnabled = ScanEngine.locationEnabled
    val history = ScanEngine.history
    val backgroundScanning = ScanService.running

    val selected = MutableStateFlow<String?>(null)
    val heatmapEnabled = MutableStateFlow(false)
    val pathLossExponent = MutableStateFlow(Calibration.pathLossExponent)

    /** Rumbo de la brújula, 0 = norte. null si el teléfono no tiene sensor. */
    val heading: StateFlow<Float?> =
        orientation.azimuths().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    /** Mediciones de la red seleccionada, solo cuando el mapa de calor está activo. */
    @OptIn(ExperimentalCoroutinesApi::class)
    val heatmapSamples: StateFlow<List<SampleEntity>> =
        combine(selected, heatmapEnabled) { bssid, on -> bssid.takeIf { on } }
            .flatMapLatest { bssid ->
                if (bssid == null) flowOf(emptyList()) else flowOf(repository.samplesFor(bssid))
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /** Escaneo mientras la app está en pantalla (se suma al del servicio si está activo). */
    fun start() = ScanEngine.start(getApplication())

    fun stop() = ScanEngine.stop()

    fun select(bssid: String?) {
        selected.value = bssid
    }

    fun toggleHeatmap() {
        heatmapEnabled.value = !heatmapEnabled.value
    }

    fun setBackgroundScanning(context: Context, enabled: Boolean) {
        if (enabled) ScanService.start(context) else ScanService.stop(context)
    }

    /** Calibra el modelo con la señal actual de una red a una distancia real conocida. */
    fun calibrate(rssi: Int, realDistanceM: Double, freqMhz: Int) {
        val exponent = Calibration.solveExponent(rssi, realDistanceM, freqMhz)
        CalibrationStore.save(getApplication(), exponent)
        pathLossExponent.value = exponent
    }

    fun resetCalibration() {
        CalibrationStore.reset(getApplication())
        pathLossExponent.value = Calibration.pathLossExponent
    }

    fun historyFor(bssid: String): List<Reading> = history.value[bssid].orEmpty()

    private val _shareReport = MutableStateFlow<Uri?>(null)
    val shareReport: StateFlow<Uri?> = _shareReport

    fun exportReport() {
        viewModelScope.launch {
            _shareReport.value = com.wifimapper.app.data.ReportExporter.buildZip(getApplication())
        }
    }

    fun consumeShareReport() {
        _shareReport.value = null
    }

    fun setPassword(bssid: String, plain: String?) {
        viewModelScope.launch { repository.setPassword(bssid, plain) }
    }

    fun clearData() {
        viewModelScope.launch {
            repository.clear()
            selected.value = null
        }
    }
}
