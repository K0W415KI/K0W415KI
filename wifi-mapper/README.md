# WifiMapper

App nativa de Android (Kotlin + Jetpack Compose) que muestra en un mapa de OpenStreetMap
las redes wifi cercanas, con su señal, posición estimada y radio de alcance.


## Funciones

- **Mapa** con tu posición, brújula (cono de orientación) y un punto por red.
- **Mapa de calor**: al elegir una red y activar "Mapa de calor", pinta por dónde caminaste
  con el color de su señal, para ver dónde llega mejor.
- **Escaneo en segundo plano**: un interruptor enciende un servicio que sigue midiendo con la
  pantalla apagada (acelera la triangulación; gasta batería; muestra una notificación fija).
- **Calibrar distancia**: parado a una distancia conocida de un router, ajustás el modelo para
  que las distancias se acerquen a la realidad de tu entorno.
- **Buscador y filtros**: por nombre/BSSID y por banda (2.4 / 5 / 6 GHz).
- **Detalle a pantalla completa** con un gráfico de cómo varió la señal en el tiempo.
- **Gráfico de ocupación de canales**: qué canal está más congestionado, para elegir el de tu
  router.
- **Exportar reporte**: genera un .zip (networks.csv, samples.csv, networks.geojson, README)
  para compartir y analizar después. No incluye contraseñas.
- **Contraseñas propias** anotadas y cifradas con el Android Keystore.

## Cómo funciona

Android informa qué redes ve el teléfono y con qué intensidad, pero no dónde está cada
router. La app lo estima:

- **Distancia**: se calcula a partir de la señal (dBm) y la frecuencia con un modelo de
  propagación log-distancia. Es aproximada: paredes y obstáculos la distorsionan.
- **Posición aproximada**: apenas se detecta una red aparece en el mapa como un aro
  hueco, a la distancia estimada. La dirección todavía no se conoce (se reparte de forma
  fija por red), así que es solo orientativa.
- **Posición triangulada**: mientras caminás, la app guarda mediciones (GPS + señal). Con
  3 o más mediciones separadas al menos 10 m, triangula el router y el punto pasa a relleno.
- **Celda**: círculo de alcance, hasta donde la señal caería a -85 dBm.

Al tocar una red (en el mapa o en la lista) se puede anotar la contraseña de **tu propia
red** en un campo; se guarda cifrada con el Android Keystore, solo en el teléfono. La app
no puede leer contraseñas guardadas por el sistema ni obtener claves de redes ajenas: eso
Android no lo permite.

Los colores indican la señal actual: verde (fuerte), amarillo, naranja, rojo (débil) y
gris (red conocida que ahora no se ve). Todos los datos quedan en el teléfono.

## Limitaciones

- Android permite a una app pedir 4 escaneos cada 2 minutos; la app pide uno cada 30 s.
  Para pruebas se puede quitar el límite en *Opciones de desarrollador → Limitación de
  búsqueda de Wi-Fi*.
- Solo escanea con la app en pantalla.
- Si caminás en línea recta, la app no puede saber de qué lado de la calle está el router.

## Compilar

Requiere JDK 17+ y el SDK de Android (plataforma 35).

```
./gradlew assembleDebug        # genera app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest    # tests del cálculo de distancia y posición
```

O abrir la carpeta en Android Studio y ejecutar en un teléfono (el emulador no escanea
redes wifi reales).

## Estructura

- `domain/SignalMath.kt`: modelo de señal y triangulación (Kotlin puro, con tests).
- `data/`: escáner wifi, GPS, base de datos Room y repositorio.
- `ui/`: pantalla del mapa (osmdroid) y lista de redes.

Mapas © colaboradores de OpenStreetMap.
