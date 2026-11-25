package com.wifimapper.app.ui

import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.drawable.BitmapDrawable
import android.location.Location
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.wifimapper.app.data.NetworkEntity
import com.wifimapper.app.data.SampleEntity
import com.wifimapper.app.domain.Locator
import com.wifimapper.app.domain.SignalMath
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.util.TileSystem
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polygon
import org.osmdroid.views.overlay.TilesOverlay

/** Radio de tolerancia del dedo al tocar un punto del mapa. */
private const val TAP_RADIUS_DP = 28

/**
 * Mapa de OpenStreetMap con tu posición, un punto por red (relleno si está triangulada,
 * hueco si es aproximada), las celdas de alcance, un cono con tu orientación y, si está
 * activo, un mapa de calor con las mediciones de la red seleccionada.
 */
@Composable
fun WifiMap(
    networks: List<NetworkEntity>,
    visible: Map<String, Int>,
    location: Location?,
    heading: Float?,
    selected: String?,
    showAllRanges: Boolean,
    heatmap: List<SampleEntity>,
    centerRequest: Int,
    palette: SignalPalette,
    darkTiles: Boolean,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val currentOnSelect = rememberUpdatedState(onSelect)
    val map = remember {
        MapView(context).apply {
            setTileSource(TileSourceFactory.MAPNIK)
            setMultiTouchControls(true)
            zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
            controller.setZoom(18.5)
            maxZoomLevel = 21.0
        }
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> map.onResume()
                Lifecycle.Event.ON_PAUSE -> map.onPause()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            map.onDetach()
        }
    }

    LaunchedEffect(location != null, centerRequest) {
        location?.let { map.controller.animateTo(GeoPoint(it.latitude, it.longitude)) }
    }
    LaunchedEffect(selected) {
        val net = networks.firstOrNull { it.bssid == selected }
        if (net?.estLat != null && net.estLon != null) {
            map.controller.animateTo(GeoPoint(net.estLat, net.estLon))
        }
    }

    AndroidView(
        factory = { map },
        modifier = modifier,
        update = { view ->
            view.overlayManager.tilesOverlay.setColorFilter(if (darkTiles) TilesOverlay.INVERT_COLORS else null)
            drawOverlays(view, networks, visible, location, heading, selected, showAllRanges, heatmap, palette) {
                currentOnSelect.value(it)
            }
        },
    )
}

private fun drawOverlays(
    map: MapView,
    networks: List<NetworkEntity>,
    visible: Map<String, Int>,
    location: Location?,
    heading: Float?,
    selected: String?,
    showAllRanges: Boolean,
    heatmap: List<SampleEntity>,
    palette: SignalPalette,
    onSelect: (String?) -> Unit,
) {
    val colorMe = palette.me.toArgb()
    val res = map.resources
    map.overlays.clear()

    val located = networks.filter { it.estLat != null && it.estLon != null }

    map.overlays.add(MapEventsOverlay(object : MapEventsReceiver {
        override fun singleTapConfirmedHelper(p: GeoPoint?): Boolean {
            if (p == null) return false
            val metersPerPixel = TileSystem.GroundResolution(p.latitude, map.zoomLevelDouble)
            val fingerM = TAP_RADIUS_DP * res.displayMetrics.density * metersPerPixel
            val hit = located
                .map { it to Locator.metersBetween(p.latitude, p.longitude, it.estLat!!, it.estLon!!) }
                .filter { (net, meters) ->
                    val cellDrawn = showAllRanges || net.bssid == selected
                    meters <= fingerM || (cellDrawn && meters <= SignalMath.rangeM(net.frequency))
                }
                .minByOrNull { it.second }
            onSelect(hit?.first?.bssid)
            return true
        }

        override fun longPressHelper(p: GeoPoint?): Boolean = false
    }))

    fun colorOf(net: NetworkEntity) = palette.argb(visible[net.bssid])

    // Mapa de calor de la red seleccionada: cada medición coloreada por su señal.
    heatmap.forEach { sample ->
        map.overlays.add(Marker(map).apply {
            position = GeoPoint(sample.lat, sample.lon)
            icon = dot(res, palette.argb(sample.rssi), 11, alpha = 150)
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
            infoWindow = null
            setOnMarkerClickListener { _, _ -> false }
        })
    }

    located.filter { showAllRanges || it.bssid == selected }.forEach { net ->
        val isSelected = net.bssid == selected
        map.overlays.add(
            circle(
                map, GeoPoint(net.estLat!!, net.estLon!!), SignalMath.rangeM(net.frequency),
                stroke = colorOf(net), fillAlpha = if (isSelected) 0x30 else 0x10,
                strokeWidth = if (isSelected) 4f else 2f, dashed = net.approximate,
            )
        )
    }

    if (location != null) {
        val me = GeoPoint(location.latitude, location.longitude)
        map.overlays.add(circle(map, me, location.accuracy.toDouble(), colorMe, fillAlpha = 0x20, strokeWidth = 1f))

        val pending = networks.firstOrNull { it.bssid == selected && (it.estLat == null || it.approximate) }
        val rssi = pending?.let { visible[it.bssid] }
        if (pending != null && rssi != null) {
            map.overlays.add(
                circle(map, me, SignalMath.distanceM(rssi, pending.frequency), palette.argb(rssi), fillAlpha = 0, strokeWidth = 5f, dashed = true)
            )
        }

        // Cono de orientación bajo el punto azul.
        if (heading != null) {
            map.overlays.add(Marker(map).apply {
                position = me
                icon = cone(res, colorMe)
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                rotation = heading
                infoWindow = null
                setOnMarkerClickListener { _, _ -> false }
            })
        }
    }

    located.sortedBy { (if (it.bssid in visible) 1 else 0) + (if (it.bssid == selected) 2 else 0) }.forEach { net ->
        map.overlays.add(Marker(map).apply {
            position = GeoPoint(net.estLat!!, net.estLon!!)
            icon = dot(res, colorOf(net), if (net.bssid == selected) 22 else 14, hollow = net.approximate)
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
            infoWindow = null
            setOnMarkerClickListener { _, _ ->
                onSelect(net.bssid)
                true
            }
        })
    }

    if (location != null) {
        map.overlays.add(Marker(map).apply {
            position = GeoPoint(location.latitude, location.longitude)
            icon = dot(res, colorMe, 18)
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
            infoWindow = null
            setOnMarkerClickListener { _, _ -> true }
        })
    }

    map.invalidate()
}

private fun circle(
    map: MapView,
    center: GeoPoint,
    radiusM: Double,
    stroke: Int,
    fillAlpha: Int,
    strokeWidth: Float,
    dashed: Boolean = false,
): Polygon = Polygon(map).apply {
    points = Polygon.pointsAsCircle(center, radiusM.coerceAtLeast(1.0))
    fillPaint.color = Color.argb(fillAlpha, Color.red(stroke), Color.green(stroke), Color.blue(stroke))
    outlinePaint.color = stroke
    outlinePaint.strokeWidth = strokeWidth
    if (dashed) outlinePaint.pathEffect = DashPathEffect(floatArrayOf(20f, 14f), 0f)
    infoWindow = null
    setOnClickListener { _, _, _ -> false }
}

private val dotCache = HashMap<List<Any>, BitmapDrawable>()

/** Punto de [sizeDp] de diámetro: relleno con borde blanco, o hueco (aro) si [hollow]. */
private fun dot(res: Resources, color: Int, sizeDp: Int, hollow: Boolean = false, alpha: Int = 255): BitmapDrawable =
    dotCache.getOrPut(listOf(color, sizeDp, hollow, alpha)) {
        val size = (sizeDp * res.displayMetrics.density).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.alpha = alpha
        paint.color = if (hollow) color else Color.WHITE
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.color = if (hollow) Color.WHITE else color
        canvas.drawCircle(size / 2f, size / 2f, size / 2f * (if (hollow) 0.55f else 0.72f), paint)
        BitmapDrawable(res, bitmap)
    }

private val coneCache = HashMap<Int, BitmapDrawable>()

/** Cono traslúcido apuntando hacia arriba (norte), para rotar con el rumbo. */
private fun cone(res: Resources, color: Int): BitmapDrawable = coneCache.getOrPut(color) {
    val size = (64 * res.displayMetrics.density).toInt()
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    paint.color = Color.argb(70, Color.red(color), Color.green(color), Color.blue(color))
    val c = size / 2f
    val path = Path().apply {
        moveTo(c, c)
        lineTo(c - size * 0.22f, c - size * 0.5f)
        lineTo(c + size * 0.22f, c - size * 0.5f)
        close()
    }
    canvas.drawPath(path, paint)
    BitmapDrawable(res, bitmap)
}
