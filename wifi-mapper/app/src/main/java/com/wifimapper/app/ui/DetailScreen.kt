package com.wifimapper.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.wifimapper.app.data.NetworkEntity
import com.wifimapper.app.data.Reading
import com.wifimapper.app.domain.SignalMath
import kotlin.math.roundToInt

/** Detalle de una red a pantalla completa, con el gráfico de señal en el tiempo. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailScreen(
    net: NetworkEntity,
    rssi: Int?,
    readings: List<Reading>,
    onSavePassword: (String?) -> Unit,
    onClose: () -> Unit,
) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column {
                TopAppBar(
                    title = { Text(net.ssid.ifEmpty { "Red oculta" }) },
                    navigationIcon = {
                        IconButton(onClick = onClose) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver")
                        }
                    },
                )
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        SignalBars(rssi?.let(SignalLevel::of))
                        Spacer(Modifier.width(12.dp))
                        Text(
                            if (rssi != null) "$rssi dBm · ~${SignalMath.distanceM(rssi, net.frequency).roundToInt()} m"
                            else "Fuera de alcance ahora",
                            style = MaterialTheme.typography.titleMedium,
                            fontFamily = FontFamily.Monospace,
                        )
                    }

                    Spacer(Modifier.height(16.dp))
                    Text("Señal en el tiempo", style = MaterialTheme.typography.titleSmall)
                    Text(
                        if (readings.size >= 2) "${readings.size} lecturas · de -30 (fuerte) a -100 dBm (débil)"
                        else "Esperando más lecturas para graficar…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                    SignalHistoryChart(readings, Modifier.fillMaxWidth().height(180.dp))

                    Spacer(Modifier.height(16.dp))
                    Text("Datos", style = MaterialTheme.typography.titleSmall)
                    Spacer(Modifier.height(4.dp))
                    DetailRow("Nombre (SSID)", net.ssid.ifEmpty { "Red oculta" })
                    DetailRow("BSSID", net.bssid, mono = true)
                    DetailRow("Banda", SignalMath.band(net.frequency))
                    DetailRow("Canal", SignalMath.channel(net.frequency)?.toString() ?: "—", mono = true)
                    DetailRow("Frecuencia", "${net.frequency} MHz", mono = true)
                    DetailRow("Seguridad", SignalMath.security(net.capabilities))
                    DetailRow("Mejor señal vista", "${net.bestRssi} dBm", mono = true)
                    DetailRow("Mediciones guardadas", net.sampleCount.toString(), mono = true)
                    DetailRow("Alcance estimado", "~${SignalMath.rangeM(net.frequency).roundToInt()} m")
                    DetailRow("Posición", if (net.estLat != null && !net.approximate) "Triangulada" else "Aproximada")

                    PasswordSection(net, onSavePassword)
                    Spacer(Modifier.height(24.dp))
                }
            }
        }
    }
}
