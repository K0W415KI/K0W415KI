package com.wifimapper.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.wifimapper.app.data.CredentialCipher
import com.wifimapper.app.data.NetworkEntity
import com.wifimapper.app.data.Reading

/** Indicador de señal de 4 barras: la cantidad de barras dice el nivel, no solo el color. */
@Composable
fun SignalBars(level: SignalLevel?, modifier: Modifier = Modifier.size(24.dp)) {
    val on = LocalSignalPalette.current.color(level)
    val off = MaterialTheme.colorScheme.outlineVariant
    Canvas(modifier) {
        val gap = size.width * 0.1f
        val barWidth = (size.width - gap * 3) / 4
        for (i in 0 until 4) {
            val barHeight = size.height * (0.4f + 0.2f * i)
            drawRoundRect(
                color = if (level != null && i < level.bars) on else off,
                topLeft = Offset(i * (barWidth + gap), size.height - barHeight),
                size = Size(barWidth, barHeight),
                cornerRadius = CornerRadius(barWidth / 3),
            )
        }
    }
}

/** Ilustración de ondas wifi. */
@Composable
fun WifiGlyph(color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val stroke = size.width * 0.07f
        val center = Offset(size.width / 2, size.height * 0.82f)
        for (i in 1..3) {
            val radius = size.width * 0.16f * i
            drawArc(
                color = color,
                startAngle = 225f,
                sweepAngle = 90f,
                useCenter = false,
                topLeft = Offset(center.x - radius, center.y - radius),
                size = Size(radius * 2, radius * 2),
                style = Stroke(stroke, cap = StrokeCap.Round),
            )
        }
        drawCircle(color, stroke * 0.9f, center)
    }
}

@Composable
fun DetailRow(label: String, value: String, mono: Boolean = false) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.Top) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(148.dp),
        )
        Text(
            value,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = if (mono) FontFamily.Monospace else null,
            modifier = Modifier.weight(1f),
        )
    }
}

/** Campo para anotar la contraseña de una red propia; se guarda cifrada. */
@Composable
fun PasswordSection(net: NetworkEntity, onSave: (String?) -> Unit) {
    var editing by rememberSaveable(net.bssid) { mutableStateOf(false) }
    var reveal by rememberSaveable(net.bssid) { mutableStateOf(false) }
    var draft by rememberSaveable(net.bssid) { mutableStateOf("") }
    val stored = remember(net.passwordEnc) { net.passwordEnc?.let(CredentialCipher::decrypt) }

    Column(Modifier.padding(top = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Lock, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text("Tu contraseña", style = MaterialTheme.typography.labelLarge)
        }
        Spacer(Modifier.height(4.dp))
        when {
            editing -> {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    singleLine = true,
                    label = { Text("Contraseña de tu red") },
                    visualTransformation = if (reveal) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    trailingIcon = {
                        TextButton(onClick = { reveal = !reveal }) { Text(if (reveal) "Ocultar" else "Mostrar") }
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
                Row {
                    TextButton(onClick = { onSave(draft); editing = false }) { Text("Guardar") }
                    TextButton(onClick = { editing = false }) { Text("Cancelar") }
                }
            }
            stored != null -> {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        if (reveal) stored else "•".repeat(stored.length.coerceAtMost(14)),
                        style = MaterialTheme.typography.bodyLarge,
                        fontFamily = FontFamily.Monospace,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    TextButton(onClick = { reveal = !reveal }) { Text(if (reveal) "Ocultar" else "Mostrar") }
                    TextButton(onClick = { draft = stored; reveal = true; editing = true }) { Text("Editar") }
                }
                TextButton(onClick = { onSave(null); reveal = false }) {
                    Text("Quitar", color = MaterialTheme.colorScheme.error)
                }
            }
            else -> TextButton(onClick = { draft = ""; reveal = false; editing = true }) { Text("Agregar contraseña") }
        }
        Text(
            "Para anotar la clave de tus propias redes. Se guarda cifrada en este teléfono.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** Gráfico de línea de la señal en el tiempo. El eje y va de -100 a -30 dBm. */
@Composable
fun SignalHistoryChart(readings: List<Reading>, modifier: Modifier = Modifier.fillMaxWidth().height(160.dp)) {
    val line = MaterialTheme.colorScheme.primary
    val grid = MaterialTheme.colorScheme.outlineVariant
    val minRssi = -100f
    val maxRssi = -30f
    Canvas(modifier) {
        val count = readings.size
        fun y(rssi: Int) = size.height * (1 - ((rssi.coerceIn(minRssi.toInt(), maxRssi.toInt()) - minRssi) / (maxRssi - minRssi)))
        // Líneas guía cada 20 dBm.
        for (dbm in intArrayOf(-40, -60, -80)) {
            val gy = y(dbm)
            drawLine(grid, Offset(0f, gy), Offset(size.width, gy), strokeWidth = 1f)
        }
        if (count >= 2) {
            val step = size.width / (count - 1)
            val path = Path()
            readings.forEachIndexed { i, r ->
                val px = i * step
                val py = y(r.rssi)
                if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
            }
            drawPath(path, line, style = Stroke(width = 3f, cap = StrokeCap.Round))
        }
    }
}
