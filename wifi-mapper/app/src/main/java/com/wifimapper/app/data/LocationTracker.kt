package com.wifimapper.app.data

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

class LocationTracker(context: Context) {
    private val manager =
        context.applicationContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    fun isEnabled(): Boolean = manager.isLocationEnabledCompat()

    /** Posiciones de GPS y de red. Se queda con la de red solo si no hay GPS reciente. */
    @SuppressLint("MissingPermission")
    fun updates(): Flow<Location> = callbackFlow {
        var lastGpsAt = 0L
        val listener = LocationListener { location ->
            val isGps = location.provider == LocationManager.GPS_PROVIDER
            if (isGps) lastGpsAt = location.elapsedRealtimeNanos
            val gpsIsFresh = location.elapsedRealtimeNanos - lastGpsAt < GPS_FRESH_NANOS
            if (isGps || !gpsIsFresh) trySend(location)
        }

        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .filter { manager.allProviders.contains(it) }
        providers.forEach { provider ->
            manager.getLastKnownLocation(provider)?.let { trySend(it) }
            manager.requestLocationUpdates(provider, 1000L, 1f, listener, Looper.getMainLooper())
        }

        awaitClose { manager.removeUpdates(listener) }
    }

    private fun LocationManager.isLocationEnabledCompat(): Boolean =
        if (android.os.Build.VERSION.SDK_INT >= 28) isLocationEnabled
        else isProviderEnabled(LocationManager.GPS_PROVIDER) || isProviderEnabled(LocationManager.NETWORK_PROVIDER)

    companion object {
        private const val GPS_FRESH_NANOS = 10_000_000_000L
    }
}
