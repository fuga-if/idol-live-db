package com.fugaif.imaslivedb.data.producercard

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import java.io.ByteArrayInputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.CardFileContents
import uniffi.imas_core.cardInviteProof
import uniffi.imas_core.cardPeerTag
import uniffi.imas_core.decodeCardFile

private const val TAG = "nearby_card"

/**
 * 近くの Android どうしで名刺ファイル (名刺 + 担当の画像) を直接渡す。圏外の会場でも届く。
 * iOS `NearbyCardExchange` (MultipeerConnectivity) の対で、手順は同じ。
 *
 * - 見せている側 ([startShowing]) は、自分の名刺の札 (`cardPeerTag`) を名乗って待つ。
 *   繋ぐ申し出は**合言葉 (`cardInviteProof`) が自分の名刺と一致したときだけ**受ける。合言葉は QR を
 *   読んだ人にしか作れないので、QR を見ずに近くで名刺を集めたり、勝手に名刺を入れたりできない。
 * - 読んだ側 ([startReading]) は、読み取った名刺から札と合言葉を作って相手を探し、繋ぐ。
 * - 繋がったら**お互いに自分の名刺ファイルを送る** (1 回のスキャンで双方向の交換になる)。
 *   読んだ側は受け取りの確認で ✓ を押してから送る ([allowSending]。× でやめたら渡さない)。
 *   読んだ側が名刺を作っていなければ送らない (片方向)。
 *
 * iPhone とは繋がらない (QR だけで成立する。画像は名刺ファイルを共有で送ってもらう)。
 * 見せている画面を閉じたら [stop] で名乗りをやめる。使い終えたら [close]。
 */
class NearbyCardExchange(context: Context) {
    enum class Phase {
        IDLE,

        /** 名乗って待っている (見せている側)。 */
        WAITING,

        /** 相手を探している (読んだ側)。 */
        SEARCHING,
        CONNECTED,

        /** 相手の名刺ファイルが届いた。 */
        RECEIVED,

        /** 相手が近くに見つからなかった・途中で切れた (読んだ側)。 */
        NOT_FOUND
    }

    private val appContext = context.applicationContext
    private val client: ConnectionsClient = Nearby.getConnectionsClient(appContext)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _phase = MutableStateFlow(Phase.IDLE)
    val phase: StateFlow<Phase> = _phase.asStateFlow()

    private val _received = MutableStateFlow<CardFileContents?>(null)

    /** 届いた名刺ファイル。 */
    val received: StateFlow<CardFileContents?> = _received.asStateFlow()

    /** 名刺ファイルが届いたとき。 */
    var onReceive: ((CardFileContents) -> Unit)? = null

    /** 今の受け渡しの番号。止めた後に古い受け渡しから届いた知らせは捨てる。 */
    private var generation = 0
    private var outgoing: ByteArray? = null
    private var targetTag: String? = null
    private var proof: ByteArray? = null
    private var isReader = false
    private val invited = mutableSetOf<String>()
    private val connected = mutableSetOf<String>()

    /** 自分の名刺を送ってよいか (見せている側は最初から、読んだ側は ✓ の後)。 */
    private var sendAllowed = false
    private var timeoutJob: Job? = null

    /** 読んだ側として、まだ相手を探している・届くのを待っている。 */
    val isWaitingForPeer: Boolean get() = _phase.value == Phase.SEARCHING || _phase.value == Phase.CONNECTED

    /** 見せている側。自分の名刺ファイルを持って名乗る。権限が無ければ名乗らない (QR だけで交換できる)。 */
    fun startShowing(payload: String, file: ByteArray) {
        stop()
        if (!NearbyCardPermissions.granted(appContext)) return
        val gen = generation
        outgoing = file
        sendAllowed = true
        proof = cardInviteProof(payload).toByteArray()
        val options = AdvertisingOptions.Builder().setStrategy(STRATEGY).build()
        client.startAdvertising(cardPeerTag(payload), SERVICE_ID, lifecycle(gen), options)
            .addOnFailureListener { Log.e(TAG, "nearby_card_advertise_failed", it) }
        _phase.value = Phase.WAITING
    }

    /** 読んだ側。読み取った名刺の相手を探す。[file] は送り返す自分の名刺ファイル (無ければ片方向)。 */
    fun startReading(payload: String, file: ByteArray?) {
        stop()
        val gen = generation
        outgoing = file
        isReader = true
        targetTag = cardPeerTag(payload)
        proof = cardInviteProof(payload).toByteArray()
        if (!NearbyCardPermissions.granted(appContext)) {
            _phase.value = Phase.NOT_FOUND
            return
        }
        _phase.value = Phase.SEARCHING
        startDiscovery(gen)
        timeoutJob = scope.launch {
            delay(SEARCH_TIMEOUT_MS)
            if (gen == generation && isWaitingForPeer) {
                _phase.value = Phase.NOT_FOUND
                client.stopDiscovery()
            }
        }
    }

    private fun startDiscovery(gen: Int) {
        val options = DiscoveryOptions.Builder().setStrategy(STRATEGY).build()
        client.startDiscovery(SERVICE_ID, discovery(gen), options).addOnFailureListener {
            Log.e(TAG, "nearby_card_browse_failed", it)
            if (gen == generation && _phase.value == Phase.SEARCHING) _phase.value = Phase.NOT_FOUND
        }
    }

    fun stop() {
        generation++
        timeoutJob?.cancel()
        timeoutJob = null
        client.stopAdvertising()
        client.stopDiscovery()
        client.stopAllEndpoints()
        outgoing = null
        targetTag = null
        proof = null
        isReader = false
        invited.clear()
        connected.clear()
        sendAllowed = false
        _received.value = null
        _phase.value = Phase.IDLE
    }

    /** 画面を閉じた。 */
    fun close() {
        stop()
        onReceive = null
        scope.cancel()
    }

    /** 読んだ側が ✓ を押した。繋がっている相手 (と、これから繋がる相手) に自分の名刺を送る。 */
    fun allowSending() {
        if (sendAllowed) return
        sendAllowed = true
        connected.forEach(::send)
    }

    private fun send(endpointId: String) {
        val bytes = outgoing
        if (!sendAllowed || bytes == null) return
        // 名刺ファイルは画像込みで 1MB を超えるので、小さな BYTES ではなく流れで送る。
        client.sendPayload(endpointId, Payload.fromStream(ByteArrayInputStream(bytes)))
            .addOnFailureListener { Log.e(TAG, "nearby_card_send_failed", it) }
    }

    // ---- 届いたもの ----

    private fun peerConnected(endpointId: String) {
        connected += endpointId
        if (_phase.value != Phase.RECEIVED && _phase.value != Phase.WAITING) _phase.value = Phase.CONNECTED
        if (isReader) client.stopDiscovery()
        send(endpointId)
    }

    private fun peerDisconnected(endpointId: String, gen: Int) {
        connected -= endpointId
        if (!isReader) return
        invited -= endpointId
        when (_phase.value) {
            // 申し出が断られた・待ち切れた。探し直して、次に見つけたらもう一度申し出る。
            Phase.SEARCHING -> {
                client.stopDiscovery()
                startDiscovery(gen)
            }
            // 届く前に切れた (相手が画面を閉じた等)。
            Phase.CONNECTED -> _phase.value = Phase.NOT_FOUND
            else -> Unit
        }
    }

    private fun dataReceived(contents: CardFileContents) {
        _received.value = contents
        if (_phase.value != Phase.WAITING) _phase.value = Phase.RECEIVED
        timeoutJob?.cancel()
        onReceive?.invoke(contents)
    }

    private fun peerFound(endpointId: String, tag: String, gen: Int) {
        val proof = proof ?: return
        if (tag != targetTag || endpointId in invited) return
        invited += endpointId
        client.requestConnection(proof, endpointId, lifecycle(gen)).addOnFailureListener {
            Log.e(TAG, "nearby_card_request_failed", it)
            if (gen == generation) invited -= endpointId
        }
    }

    // ---- 代理 ----

    private fun lifecycle(gen: Int) = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            if (gen != generation) {
                client.rejectConnection(endpointId)
                return
            }
            val accept = if (info.isIncomingConnection) {
                // 合言葉が自分の名刺と一致した相手 (= QR を読んだ人) だけを受ける。
                !isReader && proof?.contentEquals(info.endpointInfo) == true
            } else {
                // 自分から申し出た相手だけ。
                isReader && endpointId in invited
            }
            if (accept) client.acceptConnection(endpointId, payloads(gen)) else client.rejectConnection(endpointId)
        }

        override fun onConnectionResult(endpointId: String, resolution: ConnectionResolution) {
            if (gen != generation) return
            if (resolution.status.isSuccess) peerConnected(endpointId) else peerDisconnected(endpointId, gen)
        }

        override fun onDisconnected(endpointId: String) {
            if (gen != generation) return
            peerDisconnected(endpointId, gen)
        }
    }

    private fun discovery(gen: Int) = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            if (gen != generation) return
            peerFound(endpointId, info.endpointName, gen)
        }

        override fun onEndpointLost(endpointId: String) = Unit
    }

    private fun payloads(gen: Int) = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            scope.launch {
                val bytes = withContext(Dispatchers.IO) {
                    runCatching {
                        when (payload.type) {
                            Payload.Type.BYTES -> payload.asBytes()
                            Payload.Type.STREAM -> payload.asStream()?.asInputStream()?.use {
                                ProducerCardIntents.readBounded(it)
                            }
                            else -> null
                        }
                    }.onFailure { Log.e(TAG, "nearby_card_read_failed", it) }.getOrNull()
                } ?: return@launch
                if (gen != generation) return@launch
                val contents = decodeCardFile(bytes)
                if (contents == null) {
                    Log.e(TAG, "nearby_card_unreadable bytes=${bytes.size}")
                    return@launch
                }
                dataReceived(contents)
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) = Unit
    }

    private companion object {
        /** 両方の端末で同じ値。iOS の service type "imascard" と同じ名前にそろえる (繋がりはしない)。 */
        const val SERVICE_ID = "site.fugaapp.imaslivedb.imascard"

        /** 見せている 1 台に、読んだ何人もが繋ぐ形。 */
        val STRATEGY: Strategy = Strategy.P2P_STAR

        /** 読んだ側が相手を探し、届くのを待つ時間。過ぎたら「見つからない」にする (QR の中身だけで保存はできる)。 */
        const val SEARCH_TIMEOUT_MS = 15_000L
    }
}

/** Nearby Connections に要る実行時の権限 (Android の版ごと。AndroidManifest の宣言と対)。 */
object NearbyCardPermissions {
    fun required(): Array<String> = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.NEARBY_WIFI_DEVICES
        )
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> arrayOf(
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.ACCESS_FINE_LOCATION
        )
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        else -> arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION)
    }

    fun granted(context: Context): Boolean = required().all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }
}
