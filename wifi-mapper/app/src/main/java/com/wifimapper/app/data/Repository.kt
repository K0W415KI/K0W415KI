package com.wifimapper.app.data

import android.location.Location
import android.os.SystemClock
import com.wifimapper.app.domain.Locator
import com.wifimapper.app.domain.Observation
import kotlinx.coroutines.flow.Flow

class Repository(private val dao: WifiDao) {
    val networks: Flow<List<NetworkEntity>> = dao.networks()

    private var lastSampleLat = Double.NaN
    private var lastSampleLon = Double.NaN

    /**
     * Guarda un escaneo. Las redes siempre se actualizan; las mediciones para triangular
     * solo se guardan si la posición es confiable y el teléfono se movió desde la última
     * vez, porque medir muchas veces desde el mismo lugar no aporta información.
     */
    suspend fun onScan(scan: List<ScannedNetwork>, location: Location?) {
        if (scan.isEmpty()) return
        val now = System.currentTimeMillis()
        val hasFix = location != null && isFresh(location) && location.accuracy <= MAX_PROVISIONAL_ACCURACY_M
        val canSample = location != null && isUsable(location) && movedEnough(location)

        if (canSample) {
            dao.insertSamples(
                scan.map { SampleEntity(bssid = it.bssid, lat = location!!.latitude, lon = location.longitude, rssi = it.rssi, timestamp = now) }
            )
            lastSampleLat = location!!.latitude
            lastSampleLon = location.longitude
        }

        val known = dao.byBssid(scan.map { it.bssid }).associateBy { it.bssid }
        val updated = scan.map { net ->
            val old = known[net.bssid]
            var entity = NetworkEntity(
                bssid = net.bssid,
                ssid = net.ssid.ifEmpty { old?.ssid.orEmpty() },
                frequency = net.frequency,
                capabilities = net.capabilities,
                lastRssi = net.rssi,
                bestRssi = maxOf(net.rssi, old?.bestRssi ?: net.rssi),
                lastSeen = now,
                estLat = old?.estLat,
                estLon = old?.estLon,
                sampleCount = old?.sampleCount ?: 0,
                approximate = old?.approximate ?: false,
                passwordEnc = old?.passwordEnc,
            )
            if (canSample) {
                val samples = dao.samples(net.bssid)
                val estimate = Locator.estimate(samples.map { Observation(it.lat, it.lon, it.rssi) }, net.frequency)
                // Sin triangulación todavía: posición provisoria desde la medición más fuerte.
                val provisional = if (estimate == null && (entity.estLat == null || entity.approximate)) {
                    samples.firstOrNull()?.let { Locator.provisional(it.lat, it.lon, it.rssi, net.frequency, net.bssid) }
                } else null
                val position = estimate ?: provisional
                entity = entity.copy(
                    estLat = position?.lat ?: entity.estLat,
                    estLon = position?.lon ?: entity.estLon,
                    sampleCount = dao.sampleCount(net.bssid),
                    approximate = if (estimate != null) false else if (provisional != null) true else entity.approximate,
                )
            } else if (entity.estLat == null && hasFix) {
                // Primera vez que se ve la red: se la muestra ya, aunque el GPS sea impreciso.
                val p = Locator.provisional(location!!.latitude, location.longitude, net.rssi, net.frequency, net.bssid)
                entity = entity.copy(estLat = p.lat, estLon = p.lon, approximate = true)
            }
            entity
        }
        dao.upsert(updated)
    }

    /** Guarda (cifrada) o borra la contraseña que el usuario anotó para su red. */
    suspend fun setPassword(bssid: String, plain: String?) {
        val trimmed = plain?.trim().orEmpty()
        dao.setPassword(bssid, if (trimmed.isEmpty()) null else CredentialCipher.encrypt(trimmed))
    }

    /** Mediciones de una red, para dibujar el mapa de calor. */
    suspend fun samplesFor(bssid: String): List<SampleEntity> = dao.samples(bssid)

    suspend fun clear() {
        dao.clearSamples()
        dao.clearNetworks()
        lastSampleLat = Double.NaN
        lastSampleLon = Double.NaN
    }

    private fun isFresh(location: Location): Boolean =
        SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos < MAX_LOCATION_AGE_NANOS

    private fun isUsable(location: Location): Boolean = location.accuracy <= MAX_ACCURACY_M && isFresh(location)

    private fun movedEnough(location: Location): Boolean =
        lastSampleLat.isNaN() ||
            Locator.metersBetween(lastSampleLat, lastSampleLon, location.latitude, location.longitude) >= MIN_MOVE_M

    companion object {
        const val MAX_ACCURACY_M = 25f
        const val MAX_PROVISIONAL_ACCURACY_M = 100f
        const val MIN_MOVE_M = 4.0
        private const val MAX_LOCATION_AGE_NANOS = 15_000_000_000L
    }
}
