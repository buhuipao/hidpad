package com.buhuipao.hidpad

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Registers the phone as a Bluetooth HID keyboard + mouse and relays reports from Dart
 * (channel "hidpad", Dart side in lib/hid.dart).
 *
 * ponytail: Android keeps a HID app registered only while the app is visible, so the
 * computer disconnects when the user leaves the app and reconnects on return. Add a
 * connectedDevice foreground service if the link must survive in the background.
 */
@SuppressLint("MissingPermission") // start() stops before any Bluetooth call when permission is missing
class MainActivity : FlutterActivity() {
    /** How far the HID setup has come. */
    private enum class Link { NONE, BINDING, BOUND, REGISTERING, REGISTERED }

    /** Status names, the same as HidStatus in lib/hid.dart. */
    private object Status {
        const val STARTING = "starting" // waiting for the system Bluetooth service or the HID registration
        const val STALLED = "stalled" // the HID registration was not confirmed in time
        const val PERMISSION = "permission"
        const val OFF = "off"
        const val UNSUPPORTED = "unsupported"
        const val BUSY = "busy"
        const val READY = "ready"
        const val CONNECTING = "connecting"
        const val CONNECTED = "connected"
    }

    private lateinit var channel: MethodChannel
    private val adapter: BluetoothAdapter? by lazy { getSystemService(BluetoothManager::class.java)?.adapter }
    private val prefs by lazy { getPreferences(MODE_PRIVATE) }
    private var link = Link.NONE
    private var hid: BluetoothHidDevice? = null
    private var host: BluetoothDevice? = null
    private var pending: BluetoothDevice? = null // connect to this one once the current host is gone
    private var visible = false
    private var status = Status.STARTING
    // Both in SystemClock.uptimeMillis, the clock that postDelayed runs on.
    private var registerAfter = 0L // before this time the Bluetooth stack is not ready to register
    private var registeringSince = 0L // time of the last registerApp call

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(bluetoothStateReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(bluetoothStateReceiver, filter)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hidpad")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "fix" -> { fix(retry = call.arguments == true); result.success(null) }
                "state" -> result.success(state())
                "devices" -> result.success(devices())
                "connect" -> { connect(call.arguments as String); result.success(null) }
                "disconnect" -> { disconnect(); result.success(null) }
                "send" -> result.success(send(call.argument<Int>("id")!!, call.argument<ByteArray>("data")!!))
                "discoverable" -> {
                    val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
                        .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, DISCOVERABLE_SECONDS)
                    startActivityForResult(intent, 0)
                    result.success(null)
                }
                "prefs" -> result.success(prefs.all.mapValues { it.value.toString() })
                "setPref" -> {
                    prefs.edit().putString(call.argument("key"), call.argument("value")).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onStart() {
        super.onStart()
        visible = true
        start()
    }

    override fun onStop() {
        super.onStop()
        visible = false
    }

    override fun onDestroy() {
        unregisterReceiver(bluetoothStateReceiver)
        hid?.let {
            it.unregisterApp()
            adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, it)
        }
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        start()
    }

    @Deprecated("FlutterActivity is a plain Activity, so the result API is not available")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        start()
    }

    private fun hasPermission() = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        PERMISSIONS.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    /** Moves toward "registered" as far as possible without showing a dialog, and reports where it stands. */
    private fun start() {
        if (isDestroyed) return
        val adapter = adapter
        when {
            adapter == null -> push(Status.UNSUPPORTED)
            !hasPermission() -> push(Status.PERMISSION)
            !adapter.isEnabled -> push(Status.OFF)
            link == Link.NONE ->
                if (adapter.getProfileProxy(this, profileListener, BluetoothProfile.HID_DEVICE)) {
                    link = Link.BINDING
                    push(Status.STARTING)
                } else {
                    push(Status.UNSUPPORTED)
                }
            link == Link.BINDING -> push(Status.STARTING)
            // registerLater() calls start() again when the time has come.
            link == Link.BOUND && SystemClock.uptimeMillis() < registerAfter -> push(Status.STARTING)
            link == Link.BOUND -> {
                val sdp = BluetoothHidDeviceAppSdpSettings(
                    APP_NAME, "Keyboard and mouse", APP_NAME, BluetoothHidDevice.SUBCLASS1_COMBO, HID_DESCRIPTOR,
                )
                // registerApp returns false while the HID role is held, most often by another keyboard app.
                if (hid?.registerApp(sdp, null, null, mainExecutor, hidCallback) == true) {
                    link = Link.REGISTERING
                    registeringSince = SystemClock.uptimeMillis()
                    push(Status.STARTING)
                    // Come back after the timeout: an unconfirmed registration then shows as stalled.
                    window.decorView.postDelayed({ if (visible) start() }, REGISTER_TIMEOUT_MS + 1)
                } else {
                    // A failed attempt can leave the role marked as held by this app. Give it back,
                    // so the next attempt starts clean. true: this app did hold it, so try again.
                    if (hid?.unregisterApp() == true) {
                        registerLater()
                        push(Status.STARTING)
                    } else {
                        push(Status.BUSY)
                    }
                }
            }
            link == Link.REGISTERING -> push(if (registrationOverdue()) Status.STALLED else Status.STARTING)
            // REGISTERED: the status already says ready, connecting, or connected.
        }
    }

    private fun registrationOverdue() = SystemClock.uptimeMillis() - registeringSince > REGISTER_TIMEOUT_MS

    /** Registers once the Bluetooth stack has had time to clear the previous registration. */
    private fun registerLater() {
        registerAfter = SystemClock.uptimeMillis() + REREGISTER_DELAY_MS
        window.decorView.postDelayed({ if (visible) start() }, REREGISTER_DELAY_MS)
    }

    /**
     * The user asked to get going: show the dialog for whatever is missing.
     * With [retry], a registration that the system has not confirmed in time is started again.
     */
    private fun fix(retry: Boolean) {
        when {
            !hasPermission() -> requestPermissions(PERMISSIONS, 0)
            adapter?.isEnabled == false -> startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), 0)
            retry && link == Link.REGISTERING && registrationOverdue() -> {
                link = Link.BOUND
                hid?.unregisterApp()
                registerLater()
                start()
            }
            else -> start()
        }
    }

    private fun devices(): List<Map<String, String>> =
        if (!hasPermission()) emptyList()
        else adapter?.bondedDevices.orEmpty().map { mapOf("name" to (it.name ?: it.address), "address" to it.address) }

    private fun connect(address: String) {
        val proxy = hid ?: return
        if (!BluetoothAdapter.checkBluetoothAddress(address)) return
        val target = adapter?.getRemoteDevice(address) ?: return
        val current = host
        if (current != null && current != target) {
            if (proxy.disconnect(current)) pending = target
        } else {
            proxy.connect(target)
        }
    }

    private fun disconnect() {
        pending = null
        prefs.edit().remove(LAST_HOST).apply() // the user chose to leave: no auto-reconnect next time
        host?.let { hid?.disconnect(it) }
    }

    private fun send(id: Int, data: ByteArray): Boolean {
        val device = host ?: return false
        return hid?.sendReport(device, id, data) ?: false
    }

    private fun state() = mapOf("status" to status, "name" to (host?.name ?: host?.address), "address" to host?.address)

    private fun push(newStatus: String) {
        if (isDestroyed) return
        status = newStatus
        if (newStatus == Status.CONNECTED) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        channel.invokeMethod("state", state())
    }

    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            // Judge by the adapter now, not by the intent: Android can deliver this late,
            // after Bluetooth has changed again.
            if (adapter?.isEnabled != true) lostService()
            start()
        }
    }

    /** Bluetooth went off. The proxy stays and connects again by itself when Bluetooth returns. */
    private fun lostService() {
        host = null
        pending = null
        if (link != Link.NONE) link = Link.BINDING
    }

    private val profileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (isDestroyed) { // the screen closed while waiting for the service
                adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, proxy)
                return
            }
            hid = proxy as BluetoothHidDevice
            link = Link.BOUND
            start()
        }

        override fun onServiceDisconnected(profile: Int) {
            lostService()
            start()
        }
    }

    private val hidCallback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            host = null
            if (registered && visible && link == Link.REGISTERING) {
                link = Link.REGISTERED
                push(Status.READY)
                prefs.getString(LAST_HOST, null)?.let(::connect)
                return
            }
            // Android took the registration away because the app left the screen. A confirmation
            // that arrives while the app is hidden, or is not waiting for one, is void as well.
            if (link == Link.REGISTERING || link == Link.REGISTERED) link = Link.BOUND
            // Registering again right now fails: the Bluetooth stack is still clearing the old registration.
            registerLater()
            if (adapter?.isEnabled == true) push(Status.STARTING)
        }

        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            when (state) {
                BluetoothProfile.STATE_CONNECTED -> {
                    host = device
                    prefs.edit().putString(LAST_HOST, device.address).apply()
                    push(Status.CONNECTED)
                }
                BluetoothProfile.STATE_CONNECTING -> if (host == null) push(Status.CONNECTING)
                BluetoothProfile.STATE_DISCONNECTED -> {
                    if (device == host) host = null
                    if (host == null && link == Link.REGISTERED) push(Status.READY)
                    pending?.let {
                        pending = null
                        hid?.connect(it)
                    }
                }
            }
        }

        override fun onGetReport(device: BluetoothDevice, type: Byte, id: Byte, bufferSize: Int) {
            val size = HID_REPORT_SIZES[id.toInt()]
            if (size == null) hid?.reportError(device, BluetoothHidDevice.ERROR_RSP_INVALID_RPT_ID)
            else hid?.replyReport(device, type, id, ByteArray(size))
        }

        override fun onSetReport(device: BluetoothDevice, type: Byte, id: Byte, data: ByteArray) {
            hid?.reportError(device, BluetoothHidDevice.ERROR_RSP_SUCCESS) // keyboard LEDs: accept and ignore
        }
    }

    private companion object {
        const val APP_NAME = "HidPad"
        const val LAST_HOST = "lastHost"
        const val DISCOVERABLE_SECONDS = 300
        const val REREGISTER_DELAY_MS = 500L
        const val REGISTER_TIMEOUT_MS = 3000L // a registration normally confirms within a second
        val PERMISSIONS = arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
    }
}
