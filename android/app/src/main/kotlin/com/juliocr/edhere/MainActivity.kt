package com.juliocr.edhere

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.juliocr.edhere.forge.ForgeEngine

class MainActivity : FlutterActivity() {
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureForge(flutterEngine)
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
        // Mesa partilhada: fixa o ecrã na orientação em que está (pousado na
        // mesa, o tablet não pode rodar quando alguém lhe toca).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "edhere/orientation")
            .setMethodCallHandler { call, result ->
                requestedOrientation = when (call.method) {
                    "lock" -> ActivityInfo.SCREEN_ORIENTATION_LOCKED
                    else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
                result.success(null)
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

    // Bot (motor do Forge). O Forge corre nas suas threads; as respostas e os
    // estados da mesa voltam à thread principal antes de irem para o Dart.
    private val main = Handler(Looper.getMainLooper())
    private var forgeEvents: EventChannel.EventSink? = null

    private fun configureForge(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "edhere/forge/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                forgeEvents = events
            }

            override fun onCancel(arguments: Any?) {
                forgeEvents = null
            }
        })
        val sink = ForgeEngine.Sink { event -> main.post { forgeEvents?.success(event) } }
        MethodChannel(messenger, "edhere/forge").setMethodCallHandler { call, result ->
            val reply = object : ForgeEngine.Reply {
                override fun ok(value: Any?) {
                    main.post { result.success(value) }
                }

                override fun fail(code: String, message: String?) {
                    main.post { result.error(code, message, null) }
                }
            }
            when (call.method) {
                // O Forge usa APIs do Java que só existem a partir do Android 8.0.
                "supported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                "status" -> result.success(ForgeEngine.status())
                "init" -> ForgeEngine.init(this, call.argument<String>("language") ?: "en-US", reply)
                "checkDecks" -> ForgeEngine.checkDecks(call.argument("seats")!!, reply)
                "start" -> ForgeEngine.startMatch(call.arguments()!!, sink, reply)
                "stop" -> {
                    ForgeEngine.stopMatch()
                    result.success(null)
                }
                // Toques da pessoa e respostas às perguntas da partida.
                "act" -> {
                    ForgeEngine.act(call.arguments()!!)
                    result.success(null)
                }
                "pace" -> {
                    ForgeEngine.setPace(call.argument<Int>("ms")!!)
                    result.success(null)
                }
                "answer" -> {
                    ForgeEngine.answer(call.argument<Int>("id")!!, call.argument<Any>("value"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopHotspot()
        ForgeEngine.stopMatch()
        super.onDestroy()
    }
}
