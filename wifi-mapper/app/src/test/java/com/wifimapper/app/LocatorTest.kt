package com.wifimapper.app

import com.wifimapper.app.domain.Locator
import com.wifimapper.app.domain.Observation
import com.wifimapper.app.domain.SignalMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.log10
import kotlin.math.roundToInt

class LocatorTest {
    private val lat0 = -34.6037
    private val lon0 = -58.3816
    private val freq = 2437

    private fun lat(yM: Double) = lat0 + yM / 110_540.0
    private fun lon(xM: Double) = lon0 + xM / (111_320.0 * cos(Math.toRadians(lat0)))

    /** Señal que vería el teléfono en (x, y) para un router en (apX, apY), según el modelo. */
    private fun observe(x: Double, y: Double, apX: Double, apY: Double): Observation {
        val d = hypot(x - apX, y - apY).coerceAtLeast(1.0)
        val rssi = SignalMath.rssiAt1m(freq) - 10 * SignalMath.PATH_LOSS_EXPONENT * log10(d)
        return Observation(lat(y), lon(x), rssi.roundToInt())
    }

    @Test
    fun distanceGrowsAsSignalDrops() {
        assertTrue(SignalMath.distanceM(-50, freq) < SignalMath.distanceM(-70, freq))
        assertTrue(SignalMath.rangeM(5180) < SignalMath.rangeM(2437))
        assertEquals(1.0, SignalMath.distanceM(SignalMath.rssiAt1m(freq).roundToInt(), freq), 0.1)
    }

    @Test
    fun locatesRouterFromWalkAroundCorner() {
        val apX = 30.0
        val apY = 20.0
        val path = listOf(
            0.0 to 0.0, 10.0 to 0.0, 20.0 to 0.0, 30.0 to 0.0, 40.0 to 0.0,
            40.0 to 10.0, 40.0 to 20.0, 40.0 to 30.0,
        )
        val estimate = Locator.estimate(path.map { (x, y) -> observe(x, y, apX, apY) }, freq)

        assertNotNull(estimate)
        val error = Locator.metersBetween(estimate!!.lat, estimate.lon, lat(apY), lon(apX))
        assertTrue("error de $error m", error < 5.0)
    }

    @Test
    fun refusesToLocateWithoutMovement() {
        val still = List(10) { observe(0.0, 0.0, 30.0, 20.0) }
        assertNull(Locator.estimate(still, freq))
        assertNull(Locator.estimate(still.take(2), freq))
    }

    @Test
    fun provisionalPositionSitsAtEstimatedDistance() {
        val rssi = -70
        val p = Locator.provisional(lat0, lon0, rssi, freq, "aa:bb:cc:dd:ee:ff")
        val again = Locator.provisional(lat0, lon0, rssi, freq, "aa:bb:cc:dd:ee:ff")

        assertEquals(SignalMath.distanceM(rssi, freq), Locator.metersBetween(lat0, lon0, p.lat, p.lon), 0.5)
        assertEquals(p, again)
    }
}
