package com.antitourist.antitourist

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antitourist/translation_network")
            .setMethodCallHandler { call, result ->
                if (call.method != "status") {
                    result.notImplemented()
                } else {
                    val manager = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                    val active = manager.getNetworkCapabilities(manager.activeNetwork)
                    // The active network can be a VPN; check its underlying Wi-Fi too.
                    val wifi = manager.allNetworks.any { network ->
                        val capabilities = manager.getNetworkCapabilities(network)
                        capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true &&
                            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                    }
                    result.success(mapOf("connected" to (active?.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_INTERNET) == true), "wifi" to wifi))
                }
            }
    }
}
