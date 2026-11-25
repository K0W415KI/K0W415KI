package com.wifimapper.app.domain

import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.log10
import kotlin.math.pow

/**
 * Modelo de propagación log-distancia. Todo lo que sale de acá es una
 * estimación: paredes y obstáculos cambian mucho la señal real.
 */
object SignalMath {
    /** Exponente de pérdida: 2.0 es espacio libre, ~2.7 es un entorno urbano típico. */
    const val PATH_LOSS_EXPONENT = 2.7

    /** Señal por debajo de la cual una red deja de ser utilizable. */
    const val EDGE_RSSI = -85

    /** Señal esperada a 1 m del router (pérdida en espacio libre a 1 m). */
    fun rssiAt1m(freqMhz: Int): Double = 27.55 - 20 * log10(freqMhz.toDouble())

    /** Distancia estimada al router, en metros. Usa el exponente calibrado. */
    fun distanceM(rssi: Int, freqMhz: Int): Double =
        10.0.pow((rssiAt1m(freqMhz) - rssi) / (10 * Calibration.pathLossExponent)).coerceIn(1.0, 500.0)

    /** Radio de alcance estimado: distancia a la que la señal cae a [EDGE_RSSI]. */
    fun rangeM(freqMhz: Int): Double = distanceM(EDGE_RSSI, freqMhz)

    fun band(freqMhz: Int): String = when {
        freqMhz < 3000 -> "2.4 GHz"
        freqMhz < 5925 -> "5 GHz"
        else -> "6 GHz"
    }

    /** Número de canal wifi para una frecuencia central, o null si no es una banda conocida. */
    fun channel(freqMhz: Int): Int? = when (freqMhz) {
        2484 -> 14
        in 2412..2472 -> (freqMhz - 2407) / 5
        in 5160..5885 -> (freqMhz - 5000) / 5
        in 5955..7115 -> (freqMhz - 5950) / 5
        else -> null
    }

    fun security(capabilities: String): String = when {
        "SAE" in capabilities -> "WPA3"
        "WPA2" in capabilities || "RSN" in capabilities -> "WPA2"
        "WPA" in capabilities -> "WPA"
        "WEP" in capabilities -> "WEP"
        else -> "Abierta"
    }
}

/**
 * Exponente de pérdida de propagación, ajustable por el usuario. Un valor más alto significa
 * que la señal cae más rápido (más obstáculos). Lo calibra [solveExponent] parado a una
 * distancia conocida de un router. Vive en memoria; [data.CalibrationStore] lo persiste.
 */
object Calibration {
    @Volatile
    var pathLossExponent: Double = SignalMath.PATH_LOSS_EXPONENT

    fun reset() { pathLossExponent = SignalMath.PATH_LOSS_EXPONENT }

    /** Exponente que hace que [rssi] corresponda a [distanceM], acotado a un rango físico. */
    fun solveExponent(rssi: Int, distanceM: Double, freqMhz: Int): Double {
        if (distanceM <= 1.0) return pathLossExponent
        val n = (SignalMath.rssiAt1m(freqMhz) - rssi) / (10 * log10(distanceM))
        return n.coerceIn(1.6, 6.0)
    }
}

/** Una medición: dónde estaba el teléfono y con qué señal vio la red. */
data class Observation(val lat: Double, val lon: Double, val rssi: Int)

/** Posición estimada del router. [spreadM] indica cuánto se movió el teléfono al medir. */
data class Estimate(val lat: Double, val lon: Double, val spreadM: Double)

object Locator {
    /** Mediciones mínimas y recorrido mínimo para confiar en una posición. */
    const val MIN_OBSERVATIONS = 3
    const val MIN_SPREAD_M = 10.0

    private const val M_PER_DEG_LAT = 110_540.0
    private const val M_PER_DEG_LON = 111_320.0

    /**
     * Estima la posición del router a partir de mediciones tomadas en distintos lugares.
     * Arranca en el centroide ponderado por señal y lo refina minimizando la diferencia
     * entre la distancia geométrica a cada medición y la distancia que sugiere su señal.
     * Devuelve null si no hay mediciones suficientes o están todas en el mismo lugar.
     */
    fun estimate(observations: List<Observation>, freqMhz: Int): Estimate? {
        if (observations.size < MIN_OBSERVATIONS) return null

        val lat0 = observations.sumOf { it.lat } / observations.size
        val lon0 = observations.sumOf { it.lon } / observations.size
        val lonScale = M_PER_DEG_LON * cos(Math.toRadians(lat0))

        val xs = observations.map { (it.lon - lon0) * lonScale }
        val ys = observations.map { (it.lat - lat0) * M_PER_DEG_LAT }
        val spread = hypot(xs.max() - xs.min(), ys.max() - ys.min())
        if (spread < MIN_SPREAD_M) return null

        val dist = observations.map { SignalMath.distanceM(it.rssi, freqMhz) }
        val weight = dist.map { 1.0 / (it * it) }
        val weightSum = weight.sum()

        var x = xs.indices.sumOf { xs[it] * weight[it] } / weightSum
        var y = ys.indices.sumOf { ys[it] * weight[it] } / weightSum

        repeat(200) {
            var gx = 0.0
            var gy = 0.0
            for (i in xs.indices) {
                val dx = x - xs[i]
                val dy = y - ys[i]
                val r = hypot(dx, dy).coerceAtLeast(0.01)
                val err = r - dist[i]
                gx += weight[i] * err * dx / r
                gy += weight[i] * err * dy / r
            }
            x -= 0.5 * gx / weightSum
            y -= 0.5 * gy / weightSum
        }

        return Estimate(lat0 + y / M_PER_DEG_LAT, lon0 + x / lonScale, spread)
    }

    /**
     * Posición provisoria para una red que todavía no se pudo triangular: a la distancia
     * que sugiere la señal, en una dirección fija derivada de su BSSID. La distancia es
     * una estimación real; la dirección NO se conoce y solo sirve para repartir las redes
     * en el mapa hasta que haya mediciones suficientes.
     */
    fun provisional(lat: Double, lon: Double, rssi: Int, freqMhz: Int, bssid: String): Estimate {
        val distance = SignalMath.distanceM(rssi, freqMhz)
        val bearing = Math.toRadians(Math.floorMod(bssid.hashCode(), 360).toDouble())
        val lonScale = M_PER_DEG_LON * cos(Math.toRadians(lat))
        return Estimate(
            lat + distance * cos(bearing) / M_PER_DEG_LAT,
            lon + distance * kotlin.math.sin(bearing) / lonScale,
            0.0,
        )
    }

    /** Distancia en metros entre dos coordenadas cercanas. */
    fun metersBetween(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val lonScale = M_PER_DEG_LON * cos(Math.toRadians((lat1 + lat2) / 2))
        return hypot((lon2 - lon1) * lonScale, (lat2 - lat1) * M_PER_DEG_LAT)
    }
}
