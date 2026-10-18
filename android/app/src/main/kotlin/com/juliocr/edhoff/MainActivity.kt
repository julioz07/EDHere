package com.juliocr.edhoff

import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "edhere/hotspot")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startHotspot(result)
                    "stop" -> {
                        stopHotspot()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Partilhar texto (listas de decks) pela folha de partilha do Android.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "edhere/share")
            .setMethodCallHandler { call, result ->
                val send = when (call.method) {
                    "text" -> Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                    }
                    // Ficheiros (backups) da cache da app, por FileProvider.
                    "file" -> {
                        val file = File(call.argument<String>("path") ?: "")
                        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                        Intent(Intent.ACTION_SEND).apply {
                            type = call.argument<String>("mime") ?: "application/octet-stream"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    }
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                call.argument<String>("subject")?.let { send.putExtra(Intent.EXTRA_SUBJECT, it) }
                startActivity(Intent.createChooser(send, call.argument<String>("subject")))
                result.success(null)
            }
    }

    private fun startHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported", "Android 8+ required", null)
            return
        }
        reservation?.let {
            result.success(describe(it))
            return
        }
        // Até ao Android 12 o LocalOnlyHotspot falha sem a localização ligada.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val on = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                lm.isLocationEnabled
            } else {
                lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                    lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            }
            if (!on) {
                result.error("location_off", "Location services are off", null)
                return
            }
        }

        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        var replied = false
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation) {
                    reservation = r
                    if (!replied) {
                        replied = true
                        result.success(describe(r))
                    }
                }

                override fun onStopped() {
                    reservation = null
                }

                override fun onFailed(reason: Int) {
                    if (replied) return
                    replied = true
                    val code = when (reason) {
                        ERROR_INCOMPATIBLE_MODE -> "incompatible_mode"
                        ERROR_NO_CHANNEL -> "no_channel"
                        ERROR_TETHERING_DISALLOWED -> "tethering_disallowed"
                        else -> "failed_$reason"
                    }
                    result.error(code, "LocalOnlyHotspot failed ($reason)", null)
                }
            }, Handler(Looper.getMainLooper()))
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        } catch (e: IllegalStateException) {
            // Já existe um pedido ativo desta app.
            result.error("busy", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun describe(r: WifiManager.LocalOnlyHotspotReservation): Map<String, String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val c = r.softApConfiguration
            val ssid = if (Build.VERSION.SDK_INT >= 33) {
                c.wifiSsid?.toString()?.trim('"') ?: ""
            } else {
                c.ssid ?: ""
            }
            return mapOf("ssid" to ssid, "password" to (c.passphrase ?: ""))
        }
        val c = r.wifiConfiguration
        return mapOf(
            "ssid" to (c?.SSID?.trim('"') ?: ""),
            "password" to (c?.preSharedKey?.trim('"') ?: ""),
        )
    }

    private fun stopHotspot() {
        reservation?.close()
        reservation = null
    }

    override fun onDestroy() {
        stopHotspot()
        super.onDestroy()
    }
}
