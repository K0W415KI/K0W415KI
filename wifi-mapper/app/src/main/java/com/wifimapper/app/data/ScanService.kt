package com.wifimapper.app.data

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/**
 * Mantiene el escaneo andando con la app en segundo plano o la pantalla apagada, mediante una
 * notificación persistente (requisito de Android para un servicio en primer plano). Acelera
 * mucho la triangulación, a costa de batería.
 */
class ScanService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var countJob: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        startForeground(NOTIF_ID, buildNotification(ScanEngine.visible.value.size))
        ScanEngine.start(this)
        running.value = true
        countJob = scope.launch {
            ScanEngine.visible.collect { visible ->
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIF_ID, buildNotification(visible.size))
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        countJob?.cancel()
        ScanEngine.stop()
        running.value = false
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL_ID, "Escaneo en segundo plano", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Mantiene el escaneo de redes wifi activo"
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(count: Int): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("WifiMapper escaneando")
            .setContentText("$count redes a la vista · caminá para ubicarlas")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth.takeIf { false } ?: android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pending)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        val running = MutableStateFlow(false)
        private const val CHANNEL_ID = "scan"
        private const val NOTIF_ID = 1

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, ScanService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ScanService::class.java))
        }
    }
}
