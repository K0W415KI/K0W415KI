package com.wifimapper.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.wifimapper.app.data.NetworkEntity
import com.wifimapper.app.domain.SignalMath

/**
 * Calibra el modelo de distancia: el usuario se para a una distancia conocida de un router
 * visible e ingresa esa distancia; se ajusta el exponente para que coincida con la señal.
 */
@Composable
fun CalibrationDialog(
    net: NetworkEntity?,
    rssi: Int?,
    currentExponent: Double,
    onCalibrate: (Double) -> Unit,
    onReset: () -> Unit,
    onDismiss: () -> Unit,
) {
    var distance by remember { mutableStateOf("") }
    val meters = distance.replace(",", ".").toDoubleOrNull()
    val canCalibrate = net != null && rssi != null && meters != null && meters >= 1.0

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Calibrar distancia") },
        text = {
            Column {
                Text(
                    "Exponente actual: ${"%.2f".format(currentExponent)} " +
                        "(2.0 = espacio libre, más alto = más obstáculos).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(12.dp))
                if (net == null || rssi == null) {
                    Text("Elegí primero una red que estés viendo ahora (tocala en el mapa o la lista) y volvé a abrir esto.")
                } else {
                    Text("Red: ${net.ssid.ifEmpty { "Red oculta" }} · señal actual $rssi dBm.")
                    Spacer(Modifier.height(8.dp))
                    Text("Parate a una distancia conocida del router e ingresá cuántos metros hay:")
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = distance,
                        onValueChange = { distance = it },
                        singleLine = true,
                        label = { Text("Distancia real (m)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (meters != null && rssi != null) {
                        val n = com.wifimapper.app.domain.Calibration.solveExponent(rssi, meters, net.frequency)
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "Nuevo exponente: ${"%.2f".format(n)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(enabled = canCalibrate, onClick = { onCalibrate(meters!!); onDismiss() }) { Text("Calibrar") }
        },
        dismissButton = {
            TextButton(onClick = { onReset(); onDismiss() }) { Text("Restablecer") }
        },
    )
}
