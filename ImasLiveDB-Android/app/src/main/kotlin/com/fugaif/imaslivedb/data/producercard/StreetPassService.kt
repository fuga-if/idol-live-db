package com.fugaif.imaslivedb.data.producercard

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.fugaif.imaslivedb.MainActivity
import com.fugaif.imaslivedb.R
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import com.fugaif.imaslivedb.data.notification.NotificationScheduler
import com.fugaif.imaslivedb.di.AppModule
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import uniffi.imas_core.CardReceiveVia
import uniffi.imas_core.CardSamePersonChoice
import uniffi.imas_core.StreetpassFrames
import uniffi.imas_core.StreetpassRadio
import uniffi.imas_core.StreetpassSeen
import uniffi.imas_core.decodeProducerCard
import uniffi.imas_core.streetpassAccepts
import uniffi.imas_core.streetpassFingerprint
import uniffi.imas_core.streetpassFrames
import uniffi.imas_core.streetpassHeaderDecode
import uniffi.imas_core.streetpassIsActive
import uniffi.imas_core.streetpassJoin
import uniffi.imas_core.streetpassNoticeText
import uniffi.imas_core.streetpassPruneSeen
import uniffi.imas_core.streetpassShouldNotice
import uniffi.imas_core.streetpassShouldRead
import uniffi.imas_core.streetpassShowCandidate
import uniffi.imas_core.streetpassTodayCount
import uniffi.imas_core.streetpassTuning
import uniffi.imas_core.streetpassUuids

private const val TAG = "streetpass"

/**
 * すれちがいモード。オンにした端末どうしが近くに来たら、Bluetooth Low Energy で P名刺を自動で交換して
 * 名刺入れにしまう (iPhone とも届く。サーバは使わない。画像は送らない)。iOS `StreetPassService` と対。
 *
 * オンの間、(a) GATT サーバとして自分の名刺を名乗り ([startPeripheral])、(b) 同じサービスを
 * 探して 1 台ずつ繋いで読む ([startCentral])。載せ方・読み方・上限・自動オフ・文言・通信の数字はすべてコア
 * (`streetpass*`)。ここは BLE の出し入れと、読めた名刺を [ProducerCardInbox] に渡すことだけ。
 *
 * BLE はアプリが前に出ている間だけ動かす (裏に回ったら止め、前に来たら再開する。オンの設定は消さない)。
 * 裏で凍結されたプロセスが、答えない GATT サーバを名乗り続けないため。foreground service は使わない。
 * オンにした日時を端末に覚え、起動したときにオンのままなら [resumeIfNeeded] で再開する (12 時間を過ぎていたら止めて消す)。
 */
class StreetPassService(context: Context, private val module: AppModule) {
    /** 名刺入れの行が読む今の様子。 */
    data class State(
        val active: Boolean = false,
        val radio: StreetpassRadio = StreetpassRadio.UNKNOWN,
        val todayCount: UInt = 0u
    )

    private val app = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val manager: BluetoothManager? = app.getSystemService(BluetoothManager::class.java)
    private val tuning = streetpassTuning()

    private val uuids = streetpassUuids()
    private val serviceUuid: UUID = UUID.fromString(uuids.service)
    private val headerUuid: UUID = UUID.fromString(uuids.header)
    private val chunkUuids: List<UUID> = uuids.chunks.map(UUID::fromString)

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /** 今の動き。止めた後に古い BLE の知らせが届いたら捨てる。 */
    @Volatile private var generation = 0
    private var sessionJobs: List<Job> = emptyList()
    private var stateReceiver: BroadcastReceiver? = null
    private var radioRunning = false

    /** アプリが前に出ているか (ProcessLifecycleOwner の ON_START / ON_STOP)。 */
    private var inForeground = false

    /** 広告を始められなかった (radio を AdvertiseFailed にする。探すのは続ける)。 */
    private var advertiseFailed = false

    /** 名乗る値 (特性の UUID → 値)。GATT サーバの読み取りは Binder のスレッドから来るので丸ごと差し替える。 */
    @Volatile private var values: Map<UUID, ByteArray> = emptyMap()
    private var ownPayload: String? = null
    private var ownFingerprint: String? = null
    @Volatile private var gattServer: BluetoothGattServer? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var scanCallback: ScanCallback? = null

    /** 最近読んだ名刺 (指紋と日時。端末のメモリだけ)。 */
    private var recent: List<StreetpassSeen> = emptyList()

    /** 繋ぐ待ち行列 (同時に 1 台ずつ)。 */
    private val queue = StreetPassPeerQueue<BluetoothDevice>(tuning)
    private var readerJob: Job? = null

    init {
        scope.launch {
            val lifecycle = ProcessLifecycleOwner.get().lifecycle
            inForeground = lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
            lifecycle.addObserver(object : DefaultLifecycleObserver {
                override fun onStart(owner: LifecycleOwner) {
                    inForeground = true
                    if (!_state.value.active) return
                    scope.launch {
                        if (!checkStillActive()) return@launch
                        rebuildOwnPayload()
                        refreshCount()
                        applyRadio()
                    }
                }

                override fun onStop(owner: LifecycleOwner) {
                    inForeground = false
                    stopRadio()
                }
            })
        }
    }

    private fun now(): String = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()

    private fun startedAt(): String? = prefs.getString(KEY_STARTED_AT, null)

    /** オンのままか (時間を過ぎていたら止めて false)。 */
    private fun checkStillActive(): Boolean {
        if (streetpassIsActive(startedAt(), now())) return true
        end()
        return false
    }

    // ---- オン・オフ ----

    /** 起動したとき。オンのままなら再開する (時間を過ぎていたら止めて保存を消す)。 */
    fun resumeIfNeeded() {
        if (startedAt() == null || _state.value.active) return
        scope.launch { begin() }
    }

    /** 名刺入れの切替。オンは自分の名刺が無ければできない (false を返す)。 */
    suspend fun setEnabled(on: Boolean): Boolean {
        if (!on) {
            end()
            return true
        }
        if (_state.value.active) return true
        if (loadOwnPayload() == null) return false
        prefs.edit().putString(KEY_STARTED_AT, now()).apply()
        begin()
        return _state.value.active
    }

    /** 許可・Bluetooth・位置の様子を読み直す (設定から戻ってきたとき)。 */
    fun refreshRadio() {
        if (_state.value.active) applyRadio() else _state.update { it.copy(radio = currentRadio()) }
    }

    private suspend fun begin() {
        if (!checkStillActive()) return
        val payload = loadOwnPayload()
        if (payload == null) {
            // 自分の名刺が無い (消した・読めない) とオンにできない。
            end()
            return
        }
        // 読み込みの間に別の入口 (起動時の再開と切替) から始まっていたら重ねない。
        if (_state.value.active) return
        setOwnPayload(payload)
        _state.update { it.copy(active = true) }
        refreshCount()
        watchRadioState()
        val gen = generation
        sessionJobs = listOf(
            scope.launch { ProducerCardInbox.changes.collect { if (gen == generation) refreshCount() } },
            // 自分の名刺を書いたら名乗る値を作り直す。
            scope.launch {
                module.producerCardRepository.myCardChanges.collect { if (gen == generation) rebuildOwnPayload() }
            },
            // 自動オフ・今日の人数 (日付の変わり目)・名乗る値 (参加の記録などで中身が変わる) を見直す。
            scope.launch {
                while (isActive) {
                    delay(tuning.tickSeconds.toLong() * 1000)
                    if (gen != generation || !checkStillActive()) break
                    refreshCount()
                    rebuildOwnPayload()
                }
            }
        )
        applyRadio()
    }

    private fun end() {
        prefs.edit().remove(KEY_STARTED_AT).apply()
        generation++
        sessionJobs.forEach { it.cancel() }
        sessionJobs = emptyList()
        stopRadio()
        stateReceiver?.let { runCatching { app.unregisterReceiver(it) } }
        stateReceiver = null
        recent = emptyList()
        queue.reset()
        ownPayload = null
        ownFingerprint = null
        values = emptyMap()
        _state.update { it.copy(active = false) }
    }

    /** 自分の名刺の中身 (`#` の後ろ)。名刺が無ければ null。 */
    private suspend fun loadOwnPayload(): String? = runCatching {
        val card = module.producerCardRepository.myCard() ?: return@runCatching null
        val record = ProducerCardAssembler.loadMyRecord(module)
        ProducerCardAssembler.encode(card, record)?.let(ProducerCardAssembler::payload)
    }.onFailure { Log.e(TAG, "streetpass_own_card_failed", it) }.getOrNull()

    private suspend fun rebuildOwnPayload() {
        val gen = generation
        val next = loadOwnPayload()
        if (gen != generation || !_state.value.active) return
        if (next == null) end() else setOwnPayload(next)
    }

    /** 名乗る値を作り直す。コアが名乗らない (None) と言う中身なら名乗らずに探すだけにする。 */
    private fun setOwnPayload(payload: String) {
        if (payload == ownPayload) return
        ownPayload = payload
        ownFingerprint = streetpassFingerprint(payload)
        val frames: StreetpassFrames? = streetpassFrames(payload)
        if (frames == null) Log.w(TAG, "streetpass_not_advertisable bytes=${payload.length}")
        values = frames?.let { f ->
            buildMap {
                put(headerUuid, f.header)
                chunkUuids.forEachIndexed { i, id -> put(id, f.chunks.getOrNull(i) ?: ByteArray(0)) }
            }
        } ?: emptyMap()
        if (radioRunning) {
            // 名乗るかどうかが変わったら組み直す (値だけの差し替えは読み取りの度に今の値を返すので要らない)。
            val advertising = gattServer != null
            if (advertising != values.isNotEmpty()) {
                stopRadio()
                applyRadio()
            }
        }
    }

    private suspend fun countToday(): UInt? = runCatching {
        streetpassTodayCount(module.producerCardRepository.meetings().map { it.record }, now())
    }.getOrNull()

    private suspend fun refreshCount() {
        val count = countToday() ?: return
        _state.update { it.copy(todayCount = count) }
    }

    // ---- Bluetooth の様子 ----

    private fun currentRadio(): StreetpassRadio {
        val adapter = manager?.adapter ?: return StreetpassRadio.UNSUPPORTED
        if (!app.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) return StreetpassRadio.UNSUPPORTED
        if (!StreetPassPermissions.granted(app)) return StreetpassRadio.UNAUTHORIZED
        if (!adapter.isEnabled) return StreetpassRadio.POWERED_OFF
        // 広告 (名乗る) ができない端末は使えない。
        if (!adapter.isMultipleAdvertisementSupported) return StreetpassRadio.UNSUPPORTED
        // 11 以下は位置の設定が切れているとスキャンの結果が届かない。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            val location = app.getSystemService(LocationManager::class.java)
            if (location == null || !LocationManagerCompat.isLocationEnabled(location)) return StreetpassRadio.LOCATION_OFF
        }
        return StreetpassRadio.READY
    }

    private fun watchRadioState() {
        if (stateReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (_state.value.active && checkStillActive()) applyRadio()
            }
        }
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED).apply {
            addAction(LocationManager.PROVIDERS_CHANGED_ACTION)
        }
        ContextCompat.registerReceiver(app, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        stateReceiver = receiver
    }

    /**
     * 様子に合わせて動かす・止める (Bluetooth・位置を切った・許可を外した・裏に回ったら止め、戻ったら再開する)。
     */
    private fun applyRadio() {
        val radio = currentRadio()
        if (radio != StreetpassRadio.READY) advertiseFailed = false
        _state.update { it.copy(radio = if (radio == StreetpassRadio.READY && advertiseFailed) StreetpassRadio.ADVERTISE_FAILED else radio) }
        if (!_state.value.active) return
        if (radio == StreetpassRadio.READY && inForeground) {
            if (!radioRunning) startRadio()
        } else {
            stopRadio()
        }
    }

    private fun startRadio() {
        radioRunning = true
        advertiseFailed = false
        _state.update { if (it.radio == StreetpassRadio.ADVERTISE_FAILED) it.copy(radio = StreetpassRadio.READY) else it }
        if (values.isNotEmpty()) startPeripheral()
        startCentral()
    }

    @SuppressLint("MissingPermission")
    private fun stopRadio() {
        if (!radioRunning) return
        radioRunning = false
        val adapter = manager?.adapter
        runCatching {
            advertiseCallback?.let { adapter?.bluetoothLeAdvertiser?.stopAdvertising(it) }
        }.onFailure { Log.e(TAG, "streetpass_stop_advertise_failed", it) }
        advertiseCallback = null
        runCatching { gattServer?.close() }
        gattServer = null
        runCatching { scanCallback?.let { adapter?.bluetoothLeScanner?.stopScan(it) } }
            .onFailure { Log.e(TAG, "streetpass_stop_scan_failed", it) }
        scanCallback = null
        readerJob?.cancel()
        readerJob = null
        queue.clearWaiting()
    }

    // ---- (a) 名乗る: GATT サーバ + 広告 ----

    @SuppressLint("MissingPermission")
    private fun startPeripheral() {
        val manager = manager ?: return
        val server = runCatching { manager.openGattServer(app, serverCallback) }
            .onFailure { Log.e(TAG, "streetpass_gatt_server_failed", it) }.getOrNull() ?: return
        val service = BluetoothGattService(serviceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        (listOf(headerUuid) + chunkUuids).forEach { id ->
            service.addCharacteristic(
                BluetoothGattCharacteristic(id, BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ)
            )
        }
        server.addService(service)
        gattServer = server

        val advertiser = manager.adapter?.bluetoothLeAdvertiser
        if (advertiser == null) {
            advertisingFailed(gen = generation, reason = "no_advertiser")
            return
        }
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        // サービスの UUID だけを載せる (端末名は出さない)。
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(ParcelUuid(serviceUuid))
            .build()
        val gen = generation
        val callback = object : AdvertiseCallback() {
            override fun onStartFailure(errorCode: Int) {
                scope.launch { advertisingFailed(gen, "code=$errorCode") }
            }
        }
        runCatching { advertiser.startAdvertising(settings, data, callback) }
            .onSuccess { advertiseCallback = callback }
            .onFailure {
                Log.e(TAG, "streetpass_advertise_failed", it)
                advertisingFailed(gen, "exception")
            }
    }

    private fun advertisingFailed(gen: Int, reason: String) {
        Log.e(TAG, "streetpass_advertise_failed $reason")
        if (gen != generation || !radioRunning) return
        advertiseFailed = true
        _state.update { it.copy(radio = StreetpassRadio.ADVERTISE_FAILED) }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            val server = gattServer ?: return
            // 自動オフの時間を過ぎていたら読ませずに止める (tick を待たない)。
            val live = streetpassIsActive(startedAt(), now())
            val value = if (live) values[characteristic.uuid] else null
            if (!live) scope.launch { if (_state.value.active) checkStillActive() }
            runCatching {
                when {
                    value == null -> server.sendResponse(device, requestId, BluetoothGatt.GATT_READ_NOT_PERMITTED, offset, null)
                    offset > value.size -> server.sendResponse(device, requestId, BluetoothGatt.GATT_INVALID_OFFSET, offset, null)
                    // 長い値は相手が offset を付けて読み足す (long read)。offset から先を返す。
                    else -> server.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value.copyOfRange(offset, value.size))
                }
            }.onFailure { Log.e(TAG, "streetpass_read_response_failed", it) }
        }
    }

    // ---- (b) 探して読む: スキャン + 1 台ずつ繋ぐ ----

    @SuppressLint("MissingPermission")
    private fun startCentral() {
        val scanner = manager?.adapter?.bluetoothLeScanner ?: return
        val gen = generation
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) = found(result.device, gen)

            override fun onBatchScanResults(results: MutableList<ScanResult>) = results.forEach { found(it.device, gen) }

            override fun onScanFailed(errorCode: Int) {
                Log.e(TAG, "streetpass_scan_failed code=$errorCode")
            }
        }
        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(serviceUuid)).build())
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        runCatching { scanner.startScan(filters, settings, callback) }
            .onSuccess { scanCallback = callback }
            .onFailure { Log.e(TAG, "streetpass_scan_failed", it) }
    }

    /**
     * スキャンの知らせ (Binder のスレッド)。同じ相手の連続の報告・まだ繋がない相手はここで弾き、
     * 新しく行列に入ったときだけ Main に移る。
     */
    private fun found(device: BluetoothDevice, gen: Int) {
        if (gen != generation) return
        // 今日の上限に届いたら繋がない (名乗りは続ける)。
        if (!streetpassAccepts(_state.value.todayCount)) return
        if (!queue.offer(device.address, device, SystemClock.elapsedRealtime())) return
        scope.launch { if (gen == generation && radioRunning) pump() }
    }

    private fun pump() {
        if (readerJob?.isActive == true) return
        val (id, device) = queue.take(SystemClock.elapsedRealtime()) ?: return
        val gen = generation
        // 代入してから始める (始まってすぐ終わっても、2 本目を走らせない)。
        val job = scope.launch(start = CoroutineStart.LAZY) {
            val session = GattSession(app, device)
            val outcome = try {
                session.readCard(::shouldRead)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                Log.e(TAG, "streetpass_read_failed", e)
                ReadOutcome.Failed
            } finally {
                session.close()
            }
            queue.finished(id, read = outcome !is ReadOutcome.Failed, nowMs = SystemClock.elapsedRealtime())
            if (gen != generation) return@launch
            if (outcome is ReadOutcome.Read) received(outcome.payload)
            readerJob = null
            if (radioRunning) pump()
        }
        readerJob = job
        job.start()
    }

    private fun shouldRead(fingerprint: String): Boolean {
        val now = now()
        recent = streetpassPruneSeen(recent, now)
        return streetpassShouldRead(fingerprint, ownFingerprint, recent, now)
    }

    /** 読めた名刺を名刺入れへ (今日の上限・公演の選び方・知らせ)。 */
    private suspend fun received(payload: String) {
        val now = now()
        recent = streetpassPruneSeen(recent, now) + StreetpassSeen(streetpassFingerprint(payload), now)
        val before = countToday() ?: return
        _state.update { it.copy(todayCount = before) }
        if (!streetpassAccepts(before)) return
        val record = runCatching { ProducerCardAssembler.loadMyRecord(module) }.getOrNull()
        val showId = record?.let { streetpassShowCandidate(JstDay.today(), it.attended) }
        val show = showId?.let { id -> runCatching { module.producerCardRepository.showInfos(listOf(id)) }.getOrNull()?.get(id) }
        val saved = runCatching {
            // 同じ人か確かめる名刺は、聞く画面が無いので確かめずに別の名刺として足す。
            ProducerCardInbox.store(
                app, payload, emptyList(), ReceivedProducerCard.Source.APP, CardReceiveVia.STREET_PASS, show,
                choice = CardSamePersonChoice.SEPARATE
            )
        }.onFailure { Log.e(TAG, "streetpass_store_failed", it) }.getOrNull() ?: return
        Log.i(TAG, "streetpass_received card=${saved.id}")
        val after = countToday() ?: before
        _state.update { it.copy(todayCount = after) }
        if (streetpassShouldNotice(before, after)) {
            notifyIfBackground(saved.card?.name ?: decodeProducerCard(payload)?.name.orEmpty(), saved.id)
        }
    }

    // ---- 知らせ ----

    /** アプリが前に出ていないときだけ知らせる。通知の許可が無ければ出さない (ここで求めない)。 */
    @SuppressLint("MissingPermission")
    private fun notifyIfBackground(name: String, cardId: String) {
        if (inForeground || !NotificationScheduler.areNotificationsEnabled(app)) return
        val notifications = app.getSystemService(NotificationManager::class.java) ?: return
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT)
        )
        val open = PendingIntent.getActivity(
            app,
            CHANNEL_ID.hashCode(),
            Intent(app, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val text = streetpassNoticeText(name)
        val notification = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(text)
            .setAutoCancel(true)
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        runCatching { NotificationManagerCompat.from(app).notify(cardId.hashCode(), notification) }
            .onFailure { Log.e(TAG, "streetpass_notice_failed", it) }
    }

    private companion object {
        const val PREFS_NAME = "streetpass"
        const val KEY_STARTED_AT = "started_at"
        const val CHANNEL_ID = "imas_streetpass"
        const val CHANNEL_NAME = "すれちがい"

        /** 繋いだら広げてもらう MTU (欠片 480 バイトを 1 回で読めるように。BLE の上限)。 */
        const val MTU = 517
    }

    /** 1 台を読んだ結果。既に読んだ人 ([Seen]) も「読めた」と同じく、しばらく繋ぎ直さない。 */
    private sealed interface ReadOutcome {
        class Read(val payload: String) : ReadOutcome
        data object Seen : ReadOutcome
        data object Failed : ReadOutcome
    }

    /**
     * 相手 1 台との GATT の繋ぎ (central)。コールバックを順に待つだけの薄い包み。
     * 待ちはどれも `connectTimeoutSeconds` (MTU の返事だけは `mtuWaitSeconds` で、来なくても進む)。
     * 使い終えたら必ず [close]。
     */
    @SuppressLint("MissingPermission")
    private inner class GattSession(private val context: Context, private val device: BluetoothDevice) {
        private val events = Channel<GattEvent>(Channel.UNLIMITED)
        private var gatt: BluetoothGatt? = null
        private val waitMs = tuning.connectTimeoutSeconds.toLong() * 1000

        private val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                events.trySend(GattEvent.Connection(status, newState))
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                events.trySend(GattEvent.Mtu)
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                events.trySend(GattEvent.Services(status))
            }

            override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
                events.trySend(GattEvent.Read(characteristic.uuid, value, status))
            }

            @Deprecated("Android 13 未満の読み取りの知らせ")
            override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
                // 13 以上は値つきの方だけが来る (既定の実装がこちらを呼ぶが、上で受けて呼ばない)。
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    @Suppress("DEPRECATION")
                    events.trySend(GattEvent.Read(characteristic.uuid, characteristic.value, status))
                }
            }
        }

        /** [match] に当たる知らせを [timeoutMs] だけ待つ。切れた・時間切れは null。 */
        private suspend fun <T : GattEvent> await(timeoutMs: Long, match: (GattEvent) -> T?): T? =
            withTimeoutOrNull(timeoutMs) {
                var found: T? = null
                while (found == null) {
                    val event = events.receive()
                    if (event is GattEvent.Connection && event.state != BluetoothProfile.STATE_CONNECTED) break
                    found = match(event)
                }
                found
            }

        private suspend fun read(characteristic: BluetoothGattCharacteristic): ByteArray? {
            val g = gatt ?: return null
            if (!g.readCharacteristic(characteristic)) return null
            val event = await(waitMs) { e -> (e as? GattEvent.Read)?.takeIf { it.uuid == characteristic.uuid } } ?: return null
            return event.value?.takeIf { event.status == BluetoothGatt.GATT_SUCCESS }
        }

        /** 繋いで見出しを読み、読むべき名刺なら欠片を読んでつなぐ。 */
        suspend fun readCard(shouldRead: (String) -> Boolean): ReadOutcome {
            val g = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE) ?: return ReadOutcome.Failed
            gatt = g
            await(waitMs) { e -> (e as? GattEvent.Connection)?.takeIf { it.status == BluetoothGatt.GATT_SUCCESS } }
                ?: return ReadOutcome.Failed
            // MTU の返事が来ない端末もあるので、少し待って来なくても読みに進む (長い値は offset 付きで読み足される)。
            if (g.requestMtu(MTU)) {
                withTimeoutOrNull(tuning.mtuWaitSeconds.toLong() * 1000) {
                    while (true) {
                        val event = events.receive()
                        if (event is GattEvent.Mtu) break
                        if (event is GattEvent.Connection && event.state != BluetoothProfile.STATE_CONNECTED) return@withTimeoutOrNull
                    }
                }
            }
            if (!g.discoverServices()) return ReadOutcome.Failed
            val services = await(waitMs) { it as? GattEvent.Services } ?: return ReadOutcome.Failed
            if (services.status != BluetoothGatt.GATT_SUCCESS) return ReadOutcome.Failed
            val service = g.getService(serviceUuid) ?: return ReadOutcome.Failed
            val headerChar = service.getCharacteristic(headerUuid) ?: return ReadOutcome.Failed
            val header = read(headerChar)?.let(::streetpassHeaderDecode) ?: return ReadOutcome.Failed
            if (!shouldRead(header.fingerprint)) return ReadOutcome.Seen
            val chunks = chunkUuids.take(header.chunkCount.toInt()).map { id ->
                val ch = service.getCharacteristic(id) ?: return ReadOutcome.Failed
                read(ch) ?: return ReadOutcome.Failed
            }
            return streetpassJoin(header, chunks)?.let { ReadOutcome.Read(it) } ?: ReadOutcome.Failed
        }

        fun close() {
            gatt?.let { g ->
                runCatching { g.disconnect() }
                runCatching { g.close() }
            }
            gatt = null
            events.close()
        }
    }
}

/** GATT の知らせ (central の 1 台分)。 */
private sealed interface GattEvent {
    data class Connection(val status: Int, val state: Int) : GattEvent
    data object Mtu : GattEvent
    data class Services(val status: Int) : GattEvent
    class Read(val uuid: UUID, val value: ByteArray?, val status: Int) : GattEvent
}

/** すれちがいに要る実行時の権限 (Android の版ごと。AndroidManifest の宣言と対)。 */
object StreetPassPermissions {
    fun required(): Array<String> = when {
        // 12 以上は近くの端末の権限だけ (BLUETOOTH_SCAN は neverForLocation を宣言しているので位置は要らない)。
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> arrayOf(
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN
        )
        // 11 以下は BLE を探すのに位置が要る (取らない)。
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        else -> arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION)
    }

    fun granted(context: Context): Boolean = required().all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }
}
