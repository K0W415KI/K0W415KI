package com.wifimapper.app.data

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.room.Upsert
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.coroutines.flow.Flow

/** Una red vista alguna vez. estLat/estLon son null hasta tener una primera posición GPS. */
@Entity(tableName = "networks")
data class NetworkEntity(
    @PrimaryKey val bssid: String,
    val ssid: String,
    val frequency: Int,
    val capabilities: String,
    val lastRssi: Int,
    val bestRssi: Int,
    val lastSeen: Long,
    val estLat: Double? = null,
    val estLon: Double? = null,
    val sampleCount: Int = 0,
    /** true: posición provisoria (se conoce la distancia pero no la dirección). */
    val approximate: Boolean = false,
    /** Contraseña que el usuario anotó para SU red, cifrada. Null si no anotó ninguna. */
    val passwordEnc: String? = null,
)

/** Una medición de señal tomada en una posición GPS concreta. */
@Entity(tableName = "samples", indices = [Index("bssid")])
data class SampleEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val bssid: String,
    val lat: Double,
    val lon: Double,
    val rssi: Int,
    val timestamp: Long,
)

@Dao
interface WifiDao {
    @Query("SELECT * FROM networks ORDER BY lastSeen DESC")
    fun networks(): Flow<List<NetworkEntity>>

    @Query("SELECT * FROM networks WHERE bssid IN (:bssids)")
    suspend fun byBssid(bssids: List<String>): List<NetworkEntity>

    @Upsert
    suspend fun upsert(networks: List<NetworkEntity>)

    @Insert
    suspend fun insertSamples(samples: List<SampleEntity>)

    @Query("SELECT * FROM samples WHERE bssid = :bssid ORDER BY rssi DESC LIMIT 300")
    suspend fun samples(bssid: String): List<SampleEntity>

    @Query("SELECT COUNT(*) FROM samples WHERE bssid = :bssid")
    suspend fun sampleCount(bssid: String): Int

    @Query("SELECT * FROM networks")
    suspend fun allNetworks(): List<NetworkEntity>

    @Query("SELECT * FROM samples")
    suspend fun allSamples(): List<SampleEntity>

    @Query("UPDATE networks SET passwordEnc = :enc WHERE bssid = :bssid")
    suspend fun setPassword(bssid: String, enc: String?)

    @Query("DELETE FROM networks")
    suspend fun clearNetworks()

    @Query("DELETE FROM samples")
    suspend fun clearSamples()
}

val MIGRATION_2_3 = object : Migration(2, 3) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE networks ADD COLUMN passwordEnc TEXT")
    }
}

@Database(entities = [NetworkEntity::class, SampleEntity::class], version = 3, exportSchema = false)
abstract class AppDb : RoomDatabase() {
    abstract fun dao(): WifiDao

    companion object {
        @Volatile
        private var instance: AppDb? = null

        fun get(context: Context): AppDb = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(context.applicationContext, AppDb::class.java, "wifimapper.db")
                // Las mediciones son un caché, pero las contraseñas anotadas no: se migran.
                .addMigrations(MIGRATION_2_3)
                .fallbackToDestructiveMigration()
                .build().also { instance = it }
        }
    }
}
