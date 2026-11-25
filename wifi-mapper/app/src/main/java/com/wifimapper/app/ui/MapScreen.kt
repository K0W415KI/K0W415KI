package com.wifimapper.app.ui

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.tween
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.wifimapper.app.data.NetworkEntity
import com.wifimapper.app.domain.SignalMath
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

private enum class Band(val label: String) { ALL("Todas"), G24("2.4"), G5("5"), G6("6") }

private fun NetworkEntity.inBand(band: Band): Boolean = when (band) {
    Band.ALL -> true
    Band.G24 -> frequency < 3000
    Band.G5 -> frequency in 3000..5925
    Band.G6 -> frequency > 5925
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapScreen(viewModel: MainViewModel) {
    val networks by viewModel.networks.collectAsStateWithLifecycle()
    val visible by viewModel.visible.collectAsStateWithLifecycle()
    val location by viewModel.location.collectAsStateWithLifecycle()
    val heading by viewModel.heading.collectAsStateWithLifecycle()
    val selected by viewModel.selected.collectAsStateWithLifecycle()
    val locationEnabled by viewModel.locationEnabled.collectAsStateWithLifecycle()
    val heatmapEnabled by viewModel.heatmapEnabled.collectAsStateWithLifecycle()
    val heatmapSamples by viewModel.heatmapSamples.collectAsStateWithLifecycle()
    val backgroundOn by viewModel.backgroundScanning.collectAsStateWithLifecycle()
    val exponent by viewModel.pathLossExponent.collectAsStateWithLifecycle()
    val shareReport by viewModel.shareReport.collectAsStateWithLifecycle()

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val scaffoldState = rememberBottomSheetScaffoldState()

    var onlyVisible by rememberSaveable { mutableStateOf(true) }
    var showAllRanges by rememberSaveable { mutableStateOf(true) }
    var query by rememberSaveable { mutableStateOf("") }
    var band by rememberSaveable { mutableStateOf(Band.ALL) }
    var centerRequest by rememberSaveable { mutableIntStateOf(0) }
    var confirmClear by rememberSaveable { mutableStateOf(false) }
    var showCalibrate by rememberSaveable { mutableStateOf(false) }
    var showChannels by rememberSaveable { mutableStateOf(false) }
    var detailBssid by rememberSaveable { mutableStateOf<String?>(null) }

    // Compartir el reporte cuando esté listo.
    LaunchedEffect(shareReport) {
        shareReport?.let { uri ->
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "application/zip"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(Intent.createChooser(send, "Compartir reporte"))
            viewModel.consumeShareReport()
        }
    }

    val notifLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        viewModel.setBackgroundScanning(context, true)
    }
    fun toggleBackground(on: Boolean) {
        if (!on) {
            viewModel.setBackgroundScanning(context, false)
        } else if (Build.VERSION.SDK_INT >= 33) {
            notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            viewModel.setBackgroundScanning(context, true)
        }
    }

    fun matches(net: NetworkEntity): Boolean {
        if (!net.inBand(band)) return false
        if (query.isNotBlank()) {
            val q = query.trim().lowercase()
            if (!net.ssid.lowercase().contains(q) && !net.bssid.lowercase().contains(q)) return false
        }
        return true
    }

    val listed = networks
        .filter { (!onlyVisible || it.bssid in visible) && matches(it) }
        .sortedByDescending { visible[it.bssid] ?: (it.lastRssi - 200) }
    val onMap = networks.filter { (it.bssid == selected) || ((!onlyVisible || it.bssid in visible) && matches(it)) }
    val selectedNetwork = networks.firstOrNull { it.bssid == selected }
    val visibleNets = networks.mapNotNull { n -> visible[n.bssid]?.let { VisibleNet(n, it) } }

    BottomSheetScaffold(
        scaffoldState = scaffoldState,
        sheetPeekHeight = 300.dp,
        sheetContent = {
            Column(Modifier.fillMaxWidth().heightIn(max = 600.dp).navigationBarsPadding()) {
                SheetHeader(
                    visibleCount = visible.size,
                    locatedCount = networks.count { it.estLat != null && !it.approximate },
                    gpsAccuracyM = location?.accuracy?.roundToInt(),
                    backgroundOn = backgroundOn,
                    onToggleBackground = { toggleBackground(it) },
                    onCalibrate = { showCalibrate = true },
                    onChannels = { showChannels = true },
                    onExport = { viewModel.exportReport() },
                    onClear = { confirmClear = true },
                )
                if (!locationEnabled) LocationOffBanner()
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    singleLine = true,
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    placeholder = { Text("Buscar red por nombre o BSSID") },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                )
                Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Band.entries.forEach { b ->
                        FilterChip(band == b, { band = b }, label = { Text(b.label) })
                    }
                }
                Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(onlyVisible, { onlyVisible = !onlyVisible }, label = { Text("Visibles") })
                    FilterChip(showAllRanges, { showAllRanges = !showAllRanges }, label = { Text("Celdas") })
                    FilterChip(heatmapEnabled, { viewModel.toggleHeatmap() }, label = { Text("Mapa de calor") })
                }
                HorizontalDivider()
                if (listed.isEmpty()) {
                    EmptyState(waitingForScan = visible.isEmpty() && query.isBlank())
                } else {
                    LazyColumn {
                        items(listed, key = { it.bssid }) { net ->
                            NetworkRow(net, visible[net.bssid], net.bssid == selected) {
                                viewModel.select(if (net.bssid == selected) null else net.bssid)
                                scope.launch { scaffoldState.bottomSheetState.partialExpand() }
                            }
                        }
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            WifiMap(
                networks = onMap,
                visible = visible,
                location = location,
                heading = heading,
                selected = selected,
                showAllRanges = showAllRanges,
                heatmap = heatmapSamples,
                centerRequest = centerRequest,
                palette = LocalSignalPalette.current,
                darkTiles = isSystemInDarkTheme(),
                onSelect = viewModel::select,
                modifier = Modifier.fillMaxSize(),
            )

            AnimatedContent(
                targetState = selectedNetwork,
                contentKey = { it?.bssid },
                transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(130)) },
                modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(12.dp),
                label = "panel superior",
            ) { net ->
                if (net != null) {
                    SelectedCard(
                        net = net,
                        rssi = visible[net.bssid],
                        onClose = { viewModel.select(null) },
                        onSavePassword = { viewModel.setPassword(net.bssid, it) },
                        onDetail = { detailBssid = net.bssid },
                    )
                } else {
                    Legend()
                }
            }

            FloatingActionButton(
                onClick = { centerRequest++ },
                containerColor = MaterialTheme.colorScheme.surface,
                contentColor = MaterialTheme.colorScheme.primary,
                modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
            ) {
                Icon(Icons.Default.LocationOn, contentDescription = "Centrar el mapa en mi posición")
            }

            Text(
                "© OpenStreetMap",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.align(Alignment.BottomStart).padding(8.dp)
                    .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.8f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
    }

    detailBssid?.let { bssid ->
        networks.firstOrNull { it.bssid == bssid }?.let { net ->
            DetailScreen(
                net = net,
                rssi = visible[bssid],
                readings = viewModel.historyFor(bssid),
                onSavePassword = { viewModel.setPassword(bssid, it) },
                onClose = { detailBssid = null },
            )
        }
    }

    if (showCalibrate) {
        CalibrationDialog(
            net = selectedNetwork?.takeIf { visible[it.bssid] != null },
            rssi = selectedNetwork?.let { visible[it.bssid] },
            currentExponent = exponent,
            onCalibrate = { d -> selectedNetwork?.let { viewModel.calibrate(visible[it.bssid]!!, d, it.frequency) } },
            onReset = { viewModel.resetCalibration() },
            onDismiss = { showCalibrate = false },
        )
    }

    if (showChannels) {
        ChannelsScreen(visible = visibleNets, onClose = { showChannels = false })
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            icon = { Icon(Icons.Default.Delete, contentDescription = null) },
            title = { Text("¿Borrar datos?") },
            text = { Text("Se eliminan todas las redes y mediciones guardadas en este teléfono. No se puede deshacer.") },
            confirmButton = {
                TextButton(onClick = { viewModel.clearData(); confirmClear = false }) {
                    Text("Borrar", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("Cancelar") } },
        )
    }
}

@Composable
private fun SheetHeader(
    visibleCount: Int,
    locatedCount: Int,
    gpsAccuracyM: Int?,
    backgroundOn: Boolean,
    onToggleBackground: (Boolean) -> Unit,
    onCalibrate: () -> Unit,
    onChannels: () -> Unit,
    onExport: () -> Unit,
    onClear: () -> Unit,
) {
    var menu by rememberSaveable { mutableStateOf(false) }
    Row(Modifier.padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Stat(visibleCount.toString(), "visibles")
        Spacer(Modifier.width(20.dp))
        Stat(locatedCount.toString(), "ubicadas")
        Spacer(Modifier.width(20.dp))
        Stat(gpsAccuracyM?.let { "±$it m" } ?: "…", if (gpsAccuracyM != null) "GPS" else "buscando")
        Spacer(Modifier.weight(1f))
        Box {
            IconButton(onClick = { menu = true }) {
                Icon(Icons.Default.MoreVert, contentDescription = "Más opciones")
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Gráfico de canales") }, onClick = { menu = false; onChannels() })
                DropdownMenuItem(text = { Text("Calibrar distancia") }, onClick = { menu = false; onCalibrate() })
                DropdownMenuItem(text = { Text("Exportar reporte") }, onClick = { menu = false; onExport() })
                DropdownMenuItem(text = { Text("Borrar datos") }, onClick = { menu = false; onClear() })
            }
        }
    }
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 12.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text("Escanear en segundo plano", style = MaterialTheme.typography.bodyMedium)
            Text(
                "Sigue midiendo con la pantalla apagada (gasta batería).",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(checked = backgroundOn, onCheckedChange = onToggleBackground)
    }
}

@Composable
private fun Stat(value: String, label: String) {
    Column(Modifier.semantics(mergeDescendants = true) {}) {
        Text(value, style = MaterialTheme.typography.titleLarge, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold)
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun LocationOffBanner() {
    val context = LocalContext.current
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
    ) {
        Row(Modifier.padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Warning, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(
                "La ubicación del teléfono está apagada. Sin ella no se detectan redes.",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.weight(1f).padding(vertical = 8.dp),
            )
            TextButton(onClick = { context.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)) }) {
                Text("Activar", color = MaterialTheme.colorScheme.onErrorContainer, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun EmptyState(waitingForScan: Boolean) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        WifiGlyph(MaterialTheme.colorScheme.outline, Modifier.size(40.dp))
        Spacer(Modifier.height(8.dp))
        Text(if (waitingForScan) "Buscando redes…" else "No hay redes para mostrar", style = MaterialTheme.typography.titleSmall)
        Text(
            if (waitingForScan) "El primer escaneo puede tardar hasta 30 segundos." else "Probá cambiar los filtros o la búsqueda.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

private fun NetworkEntity.displayName() = ssid.ifEmpty { "Red oculta" }

@Composable
private fun NetworkRow(net: NetworkEntity, rssi: Int?, isSelected: Boolean, onClick: () -> Unit) {
    val level = rssi?.let(SignalLevel::of)
    val located = net.estLat != null && !net.approximate
    Row(
        Modifier.fillMaxWidth()
            .heightIn(min = 64.dp)
            .background(if (isSelected) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent)
            .selectable(selected = isSelected, role = androidx.compose.ui.semantics.Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = "${net.displayName()}, señal ${level?.label ?: "fuera de alcance"}, " +
                    if (located) "posición triangulada" else "posición aproximada"
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SignalBars(level)
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(net.displayName(), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (located) {
                    Icon(Icons.Default.LocationOn, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(2.dp))
                }
                Text(
                    "${if (located) "Triangulada" else "Aproximada"} · ${SignalMath.band(net.frequency)} · ${SignalMath.security(net.capabilities)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(horizontalAlignment = Alignment.End) {
            Text(if (rssi != null) "$rssi dBm" else "—", style = MaterialTheme.typography.bodyMedium, fontFamily = FontFamily.Monospace)
            Text(
                if (rssi != null) "~${SignalMath.distanceM(rssi, net.frequency).roundToInt()} m" else "fuera de alcance",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SelectedCard(net: NetworkEntity, rssi: Int?, onClose: () -> Unit, onSavePassword: (String?) -> Unit, onDetail: () -> Unit) {
    val level = rssi?.let(SignalLevel::of)
    Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surface, shadowElevation = 6.dp, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(start = 16.dp, bottom = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SignalBars(level)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                    Text(net.displayName(), style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        "${SignalMath.band(net.frequency)} · ${SignalMath.security(net.capabilities)} · ${net.bssid}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                IconButton(onClick = onClose) { Icon(Icons.Default.Close, contentDescription = "Cerrar detalle") }
            }
            Row(Modifier.padding(end = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Metric("Señal", if (rssi != null) "$rssi dBm" else "—", level?.label ?: "Sin señal", Modifier.weight(1f))
                Metric("Distancia", if (rssi != null) "~${SignalMath.distanceM(rssi, net.frequency).roundToInt()} m" else "—", "desde vos", Modifier.weight(1f))
                Metric("Alcance", "~${SignalMath.rangeM(net.frequency).roundToInt()} m", "radio", Modifier.weight(1f))
            }
            Spacer(Modifier.height(8.dp))
            Text(
                if (net.estLat != null && !net.approximate) "Posición triangulada con ${net.sampleCount} mediciones."
                else "Posición aproximada: la distancia es estimada pero la dirección no se conoce. Caminá unos metros para triangularla.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(end = 16.dp),
            )
            Box(Modifier.padding(end = 16.dp)) { PasswordSection(net, onSavePassword) }
            TextButton(onClick = onDetail) { Text("Ver detalle y gráfico de señal") }
        }
    }
}

@Composable
private fun Metric(label: String, value: String, caption: String, modifier: Modifier = Modifier) {
    Column(
        modifier.background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp).semantics(mergeDescendants = true) {},
    ) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleMedium, fontFamily = FontFamily.Monospace, maxLines = 1)
        Text(caption, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
    }
}

@Composable
private fun Legend() {
    val palette = LocalSignalPalette.current
    Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f), shadowElevation = 3.dp) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.semantics(mergeDescendants = true) { contentDescription = "Colores de señal, de fuerte a débil" },
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                LegendText("Fuerte")
                SignalLevel.entries.forEach { level -> Box(Modifier.size(10.dp).background(palette.color(level), CircleShape)) }
                LegendText("Débil")
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(10.dp).background(palette.unseen, CircleShape))
                LegendText("Sin señal")
            }
        }
    }
}

@Composable
private fun LegendText(text: String) {
    Text(text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface, maxLines = 1)
}
