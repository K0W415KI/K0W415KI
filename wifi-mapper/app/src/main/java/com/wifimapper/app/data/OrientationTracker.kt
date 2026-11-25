package com.wifimapper.app.data

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/** Rumbo del teléfono en grados (0 = norte). Aproximado: conviene sostener el teléfono plano. */
class OrientationTracker(context: Context) {
    private val sensorManager =
        context.applicationContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    fun azimuths(): Flow<Float> = callbackFlow {
        val sensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (sensor == null) {
            close()
            return@callbackFlow
        }
        val rotation = FloatArray(9)
        val orientation = FloatArray(3)
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(rotation, event.values)
                SensorManager.getOrientation(rotation, orientation)
                val degrees = ((Math.toDegrees(orientation[0].toDouble()) + 360) % 360).toFloat()
                trySend(degrees)
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sensorManager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
        awaitClose { sensorManager.unregisterListener(listener) }
    }
}
