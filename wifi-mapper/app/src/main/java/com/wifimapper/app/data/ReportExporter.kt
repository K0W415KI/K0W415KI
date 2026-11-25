package com.wifimapper.app.data

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import com.wifimapper.app.domain.Calibration
import com.wifimapper.app.domain.SignalMath
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Arma un .zip con el relevamiento para compartir y analizar después. NO incluye las
 * contraseñas anotadas: el reporte es solo de señal y posiciones.
 */
object ReportExporter {
    suspend fun buildZip(context: Context): Uri = withContext(Dispatchers.IO) {
        val dao = ScanEngine.repository(context).let { AppDb.get(context).dao() }
        val networks = dao.allNetworks()
        val samples = dao.allSamples()

        val dir = File(context.cacheDir, "reports").apply { mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val file = File(dir, "wifimapper-$stamp.zip")

        ZipOutputStream(file.outputStream().buffered()).use { zip ->
            zip.putNextEntry(ZipEntry("networks.csv"))
            zip.write(networksCsv(networks).toByteArray())
            zip.closeEntry()

            zip.putNextEntry(ZipEntry("samples.csv"))
            zip.write(samplesCsv(samples).toByteArray())
            zip.closeEntry()

            zip.putNextEntry(ZipEntry("networks.geojson"))
            zip.write(geoJson(networks).toByteArray())
            zip.closeEntry()

            zip.putNextEntry(ZipEntry("README.txt"))
            zip.write(readme(networks.size, samples.size).toByteArray())
            zip.closeEntry()
        }

        FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    }

    private fun q(value: String) = "\"" + value.replace("\"", "\"\"") + "\""

    private fun networksCsv(networks: List<NetworkEntity>): String = buildString {
        appendLine("bssid,ssid,band,channel,frequency_mhz,security,best_rssi,last_rssi,est_lat,est_lon,approximate,sample_count,last_seen")
        for (n in networks) {
            appendLine(
                listOf(
                    q(n.bssid), q(n.ssid), q(SignalMath.band(n.frequency)),
                    SignalMath.channel(n.frequency)?.toString() ?: "", n.frequency.toString(),
                    q(SignalMath.security(n.capabilities)), n.bestRssi.toString(), n.lastRssi.toString(),
                    n.estLat?.toString() ?: "", n.estLon?.toString() ?: "", n.approximate.toString(),
                    n.sampleCount.toString(), n.lastSeen.toString(),
                ).joinToString(","),
            )
        }
    }

    private fun samplesCsv(samples: List<SampleEntity>): String = buildString {
        appendLine("bssid,lat,lon,rssi,timestamp")
        for (s in samples) appendLine("${q(s.bssid)},${s.lat},${s.lon},${s.rssi},${s.timestamp}")
    }

    private fun geoJson(networks: List<NetworkEntity>): String = buildString {
        append("{\"type\":\"FeatureCollection\",\"features\":[")
        val located = networks.filter { it.estLat != null && it.estLon != null }
        located.forEachIndexed { i, n ->
            if (i > 0) append(",")
            append("{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[${n.estLon},${n.estLat}]},")
            append("\"properties\":{\"ssid\":${q(n.ssid)},\"bssid\":${q(n.bssid)},")
            append("\"band\":${q(SignalMath.band(n.frequency))},\"best_rssi\":${n.bestRssi},")
            append("\"range_m\":${SignalMath.rangeM(n.frequency).toInt()},\"approximate\":${n.approximate}}}")
        }
        append("]}")
    }

    private fun readme(networkCount: Int, sampleCount: Int): String = """
        Relevamiento de WifiMapper
        ==========================
        Redes: $networkCount
        Mediciones: $sampleCount
        Exponente de calibración usado: ${"%.2f".format(Locale.US, Calibration.pathLossExponent)}

        Archivos:
        - networks.csv: una fila por red (nombre, canal, seguridad, mejor señal, posición estimada).
        - samples.csv: cada medición de señal con su posición GPS (para mapas de calor / reanálisis).
        - networks.geojson: redes ubicadas, abribles en Google Earth, QGIS, geojson.io.

        No incluye contraseñas. Las distancias y posiciones son estimaciones.
    """.trimIndent()
}
