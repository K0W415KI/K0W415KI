package com.wifimapper.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.wifimapper.app.data.NetworkEntity
import com.wifimapper.app.domain.SignalMath

/** Red visible con su señal actual, para el gráfico de canales. */
data class VisibleNet(val net: NetworkEntity, val rssi: Int)

/**
 * Ocupación de canales: cuántas redes (y con qué señal) hay en cada canal, por banda.
 * Sirve para elegir un canal menos congestionado para tu propio router.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelsScreen(visible: List<VisibleNet>, onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column {
                TopAppBar(
                    title = { Text("Ocupación de canales") },
                    navigationIcon = {
                        IconButton(onClick = onClose) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver")
                        }
                    },
                )
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
                    Text(
                        "Cada barra es un canal. Más alto = red más fuerte; el número arriba es cuántas redes lo usan. " +
                            "Para tu router, elegí un canal con barras bajas o vacío.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    BandChart("2.4 GHz", (1..13).toList(), visible.filter { it.net.frequency < 3000 })
                    BandChart("5 GHz", listOf(36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 149, 153, 157, 161, 165), visible.filter { it.net.frequency in 5000..5925 })
                    val sixGhz = visible.filter { it.net.frequency >= 5955 }
                    if (sixGhz.isNotEmpty()) {
                        BandChart("6 GHz", sixGhz.mapNotNull { SignalMath.channel(it.net.frequency) }.distinct().sorted(), sixGhz)
                    }
                }
            }
        }
    }
}

@Composable
private fun BandChart(title: String, channels: List<Int>, nets: List<VisibleNet>) {
    val barColor = MaterialTheme.colorScheme.primary
    val axis = MaterialTheme.colorScheme.outlineVariant
    val label = MaterialTheme.colorScheme.onSurfaceVariant
    Spacer(Modifier.height(20.dp))
    Text("$title · ${nets.size} redes", style = MaterialTheme.typography.titleSmall)
    Spacer(Modifier.height(8.dp))
    if (nets.isEmpty()) {
        Text("Sin redes en esta banda.", style = MaterialTheme.typography.bodySmall, color = label)
        return
    }
    val byChannel = channels.associateWith { ch -> nets.filter { SignalMath.channel(it.net.frequency) == ch } }
    val textPaint = android.graphics.Paint().apply {
        color = label.toArgbCompat()
        textSize = 26f
        textAlign = android.graphics.Paint.Align.CENTER
        isAntiAlias = true
    }
    Canvas(Modifier.fillMaxWidth().height(160.dp)) {
        val n = channels.size
        val slot = size.width / n
        val barWidth = slot * 0.6f
        val baseY = size.height - 30f
        drawLine(axis, Offset(0f, baseY), Offset(size.width, baseY), strokeWidth = 1f)
        channels.forEachIndexed { i, ch ->
            val cx = slot * i + slot / 2
            val here = byChannel[ch].orEmpty()
            if (here.isNotEmpty()) {
                // Altura según la red más fuerte del canal (de -95 a -40 dBm).
                val best = here.maxOf { it.rssi }
                val frac = ((best + 95f) / 55f).coerceIn(0.05f, 1f)
                val barHeight = (baseY - 10f) * frac
                drawBar(cx, baseY, barWidth, barHeight, barColor.toArgbCompat())
                drawContext.canvas.nativeCanvas.drawText(here.size.toString(), cx, baseY - barHeight - 8f, textPaint)
            }
            if (i % (if (n > 20) 3 else 1) == 0) {
                drawContext.canvas.nativeCanvas.drawText(ch.toString(), cx, size.height - 6f, textPaint)
            }
        }
    }
}

private fun DrawScope.drawBar(cx: Float, baseY: Float, width: Float, height: Float, color: Int) {
    drawRoundRect(
        color = androidx.compose.ui.graphics.Color(color),
        topLeft = Offset(cx - width / 2, baseY - height),
        size = Size(width, height),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(width / 4),
    )
}

private fun androidx.compose.ui.graphics.Color.toArgbCompat(): Int = this.toArgb()
