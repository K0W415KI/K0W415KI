package com.wifimapper.app.data

import android.content.Context
import com.wifimapper.app.domain.Calibration
import com.wifimapper.app.domain.SignalMath

/** Carga y guarda el exponente de calibración en SharedPreferences. */
object CalibrationStore {
    private const val PREFS = "calibration"
    private const val KEY = "path_loss_exponent"

    fun load(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stored = prefs.getFloat(KEY, SignalMath.PATH_LOSS_EXPONENT.toFloat())
        Calibration.pathLossExponent = stored.toDouble()
    }

    fun save(context: Context, exponent: Double) {
        Calibration.pathLossExponent = exponent
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putFloat(KEY, exponent.toFloat()).apply()
    }

    fun reset(context: Context) {
        Calibration.reset()
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY).apply()
    }
}
