package com.wifimapper.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb

// Sistema de diseño: azul "escaneo" sobre grises pizarra, con colores de estado para la
// señal. Todos los colores de la app salen de estos tokens; no hay hex sueltos en pantallas.

private val LightColors = lightColorScheme(
    primary = Color(0xFF2563EB),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFDBEAFE),
    onPrimaryContainer = Color(0xFF1E3A8A),
    secondary = Color(0xFF475569),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFDBEAFE),
    onSecondaryContainer = Color(0xFF1E3A8A),
    background = Color(0xFFF8FAFC),
    onBackground = Color(0xFF1E293B),
    surface = Color.White,
    onSurface = Color(0xFF1E293B),
    surfaceVariant = Color(0xFFF1F5F9),
    onSurfaceVariant = Color(0xFF475569),
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = Color.White,
    surfaceContainer = Color(0xFFF8FAFC),
    surfaceContainerHigh = Color(0xFFF1F5F9),
    surfaceContainerHighest = Color(0xFFE2E8F0),
    outline = Color(0xFF64748B),
    outlineVariant = Color(0xFFE2E8F0),
    error = Color(0xFFDC2626),
    onError = Color.White,
    errorContainer = Color(0xFFFEE2E2),
    onErrorContainer = Color(0xFF7F1D1D),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF60A5FA),
    onPrimary = Color(0xFF0B1220),
    primaryContainer = Color(0xFF1E3A8A),
    onPrimaryContainer = Color(0xFFDBEAFE),
    secondary = Color(0xFF94A3B8),
    onSecondary = Color(0xFF0B1220),
    secondaryContainer = Color(0xFF1E3A5F),
    onSecondaryContainer = Color(0xFFDBEAFE),
    background = Color(0xFF0B1220),
    onBackground = Color(0xFFE2E8F0),
    surface = Color(0xFF0F172A),
    onSurface = Color(0xFFE2E8F0),
    surfaceVariant = Color(0xFF1E293B),
    onSurfaceVariant = Color(0xFFA7B4C6),
    surfaceContainerLowest = Color(0xFF0B1220),
    surfaceContainerLow = Color(0xFF131C2E),
    surfaceContainer = Color(0xFF1E293B),
    surfaceContainerHigh = Color(0xFF243044),
    surfaceContainerHighest = Color(0xFF334155),
    outline = Color(0xFF64748B),
    outlineVariant = Color(0xFF334155),
    error = Color(0xFFF87171),
    onError = Color(0xFF450A0A),
    errorContainer = Color(0xFF7F1D1D),
    onErrorContainer = Color(0xFFFEE2E2),
)

/** Nivel de señal. Siempre se muestra con barras y texto además del color. */
enum class SignalLevel(val bars: Int, val label: String) {
    Excellent(4, "Excelente"),
    Good(3, "Buena"),
    Fair(2, "Regular"),
    Weak(1, "Débil");

    companion object {
        fun of(rssi: Int): SignalLevel = when {
            rssi >= -55 -> Excellent
            rssi >= -70 -> Good
            rssi >= -80 -> Fair
            else -> Weak
        }
    }
}

/** Colores de estado de la señal, compartidos por la lista y el mapa. */
data class SignalPalette(
    val excellent: Color,
    val good: Color,
    val fair: Color,
    val weak: Color,
    /** Red conocida que ahora no se ve. */
    val unseen: Color,
    /** Tu posición. */
    val me: Color,
) {
    fun color(level: SignalLevel?): Color = when (level) {
        SignalLevel.Excellent -> excellent
        SignalLevel.Good -> good
        SignalLevel.Fair -> fair
        SignalLevel.Weak -> weak
        null -> unseen
    }

    fun argb(rssi: Int?): Int = color(rssi?.let(SignalLevel::of)).toArgb()
}

private val LightSignal = SignalPalette(
    excellent = Color(0xFF15803D),
    good = Color(0xFF65A30D),
    fair = Color(0xFFD97706),
    weak = Color(0xFFDC2626),
    unseen = Color(0xFF64748B),
    me = Color(0xFF2563EB),
)

private val DarkSignal = SignalPalette(
    excellent = Color(0xFF4ADE80),
    good = Color(0xFFA3E635),
    fair = Color(0xFFFBBF24),
    weak = Color(0xFFF87171),
    unseen = Color(0xFF94A3B8),
    me = Color(0xFF60A5FA),
)

val LocalSignalPalette = staticCompositionLocalOf { LightSignal }

@Composable
fun WifiMapperTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    CompositionLocalProvider(LocalSignalPalette provides if (dark) DarkSignal else LightSignal) {
        MaterialTheme(colorScheme = if (dark) DarkColors else LightColors, content = content)
    }
}
