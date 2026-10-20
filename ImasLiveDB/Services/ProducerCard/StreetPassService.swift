@preconcurrency import CoreBluetooth
import Foundation
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "streetpass")

extension Notification.Name {
    /// 自分の名刺を書き直した。すれちがいの名乗る値を作り直す。
    static let myProducerCardChanged = Notification.Name("myProducerCardChanged")
}

/// P名刺のすれちがいモード。オンにした端末どうしが近くに来たら、Bluetooth Low Energy で名刺を自動で交換して
/// 名刺入れにしまう (Android とも届く。サーバは使わない。画像は送らない)。
///
/// オンの間、**GATT サーバとして名乗る** (読み取り専用の特性 4 つ: 見出しと欠片 3 つ。広告にはサービスの UUID だけ) と
/// **探して読む** (サービスで絞ってスキャンし、見つけた相手に 1 台ずつ繋いで見出し → 欠片の順に読む) を同時に行う。
///
/// 何をどう載せて読むか (欠片の分け方・見出し・指紋・読み直さない間・1 日の上限・自動オフ・文言) はすべてコア
/// (`streetpass*`)。通信の段取りの数字 (繋ぎ直さない間・待ち行列・1 台の待ち時間・見直しの間) もコアの
/// `streetpassTuning()`。ここは BLE の出し入れだけをする。
///
/// 裏にいる間も動くように、central / peripheral の state restoration を付ける (起動時に `resumeIfActive()`)。
@MainActor @Observable
final class StreetPassService: NSObject {
    static let shared = StreetPassService()

    /// オンにした日時 (ISO 8601)。無ければオフ。
    private static let startedAtKey = "streetpass_started_at"
    private static let peripheralRestoreId = "com.fugaif.ImasLiveDB.streetpass.peripheral"
    private static let centralRestoreId = "com.fugaif.ImasLiveDB.streetpass.central"
    private static let tuning = streetpassTuning()

    /// オンになっている (オンにしてから決まった時間の内)。
    private(set) var isOn = false
    /// 自分の名刺を作ってある (無いとオンにできない)。
    private(set) var hasCard = false
    /// 今日すれちがった人数。
    private(set) var todayCount: UInt32 = 0
    /// Bluetooth の様子。
    private(set) var radio: StreetpassRadio = .unknown

    /// 名刺入れの行に出す様子。
    var status: StreetpassStatus {
        streetpassStatus(active: isOn, hasCard: hasCard, todayCount: todayCount, radio: radio)
    }

    /// 繋いで読んでいる相手 1 台。
    private struct Reading {
        let peripheral: CBPeripheral
        let timeout: Task<Void, Never>
        var characteristics: [CBUUID: CBCharacteristic] = [:]
        var header: StreetpassHeader?
        var chunks: [Data] = []
    }

    @ObservationIgnored private let serviceUUID: CBUUID
    @ObservationIgnored private let headerUUID: CBUUID
    @ObservationIgnored private let chunkUUIDs: [CBUUID]

    @ObservationIgnored private var peripheralManager: CBPeripheralManager?
    @ObservationIgnored private var centralManager: CBCentralManager?
    @ObservationIgnored private var ownPayload: String?
    @ObservationIgnored private var frames: StreetpassFrames?
    @ObservationIgnored private var ownFingerprint: String?
    @ObservationIgnored private var serviceAdded = false
    /// 広告を始められなかった (次に始められるまで)。
    @ObservationIgnored private var advertiseFailed = false
    /// 期限切れで起こされた (復元の識別子で作った manager を、状態が分かったところで止める)。
    @ObservationIgnored private var haltingRestored = false
    /// 最近読んだ名刺 (保存しない)。
    @ObservationIgnored private var recent: [StreetpassSeen] = []
    /// 繋ぐ待ち行列と、端末ごとの次に繋いでよい時刻 (端末のメモリだけで持つ)。
    @ObservationIgnored private var queue = StreetPassQueue<UUID>(tuning: StreetPassService.tuning)
    /// 待ち行列にいる相手。
    @ObservationIgnored private var found: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var current: Reading?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    override private init() {
        let uuids = streetpassUuids()
        serviceUUID = CBUUID(string: uuids.service)
        headerUUID = CBUUID(string: uuids.header)
        chunkUUIDs = uuids.chunks.map { CBUUID(string: $0) }
        super.init()
        NotificationCenter.default.addObserver(forName: .myProducerCardChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in await StreetPassService.shared.refresh() }
        }
    }

    // MARK: - オン・オフ

    /// 起動時。オンのままなら再開し、時間を過ぎていればオフにして保存を消す。
    func resumeIfActive() {
        guard let startedAt = Self.storedStartedAt else { return }
        guard streetpassIsActive(startedAt: startedAt, now: Self.now()) else {
            // 期限切れのまま裏で起こされたとき、OS が前の起動の名乗り・スキャンを続けていることがある。
            // 同じ復元の識別子で作り直し、状態が分かったところで明示的に止める。
            Self.clearStartedAt()
            haltingRestored = true
            startRadios()
            return
        }
        isOn = true
        startRadios()
        Task { await refresh() }
    }

    /// 前面に来たとき。自動オフを確かめ、名乗る名刺 (担当・参加の記録が変わっているかもしれない) を作り直す。
    func sceneBecameActive() {
        guard checkExpiry() else { return }
        Task { await refresh() }
    }

    /// 自分の名刺と今日すれちがった人数を読み直す (名刺入れの画面が開くとき・名刺入れが変わったとき)。
    func refresh() async {
        await loadOwnCard()
        await refreshTodayCount()
        checkExpiry()
    }

    func turnOn() async {
        guard !isOn else { return }
        // 切替がすぐ動くように先にオンにし、名刺が無ければ戻す。
        isOn = true
        await loadOwnCard()
        guard isOn else { return }
        guard hasCard else {
            isOn = false
            return
        }
        UserDefaults.standard.set(Self.now(), forKey: Self.startedAtKey)
        startRadios()
        await refreshTodayCount()
    }

    func turnOff() {
        Self.clearStartedAt()
        isOn = false
        stopRadios()
    }

    // MARK: - 自分の名刺

    private func loadOwnCard() async {
        guard await Self.ensureDatabase() else { return }
        let store = AppContainer.shared.producerCards
        var payload: String?
        if let mine = try? await store.myCard(), let record = try? await ProducerCardAssembler.loadMyRecord(),
           let encoded = ProducerCardAssembler.encode(card: mine, record: record) {
            payload = ProducerCardAssembler.payload(of: encoded)
        }
        hasCard = payload != nil
        guard payload != ownPayload else { return }
        ownPayload = payload
        frames = payload.flatMap { streetpassFrames(payload: $0) }
        ownFingerprint = payload.map { streetpassFingerprint(payload: $0) }
        guard isOn else { return }
        if payload == nil {
            // 名刺を消した。名刺が無いとオンにできない。
            if Self.storedStartedAt != nil { turnOff() }
        } else if let peripheralManager {
            // 特性の値は読まれたときに今の値で答えるので、作り直すのは名乗れるかどうかだけ。
            advertise(peripheralManager)
        }
    }

    private func refreshTodayCount() async {
        guard await Self.ensureDatabase() else { return }
        let meetings = ((try? await AppContainer.shared.producerCards.meetings(cardId: nil)) ?? []).map(\.record)
        todayCount = streetpassTodayCount(meetings: meetings, now: Self.now())
    }

    // MARK: - 受け取り

    /// 読めた名刺を名刺入れにしまう。今日の上限に届いていればしまわない。
    private func receive(_ payload: String) async {
        guard await Self.ensureDatabase() else { return }
        await refreshTodayCount()
        let before = todayCount
        guard streetpassAccepts(todayCount: before) else { return }
        let record = try? await ProducerCardAssembler.loadMyRecord()
        // すれちがいの公演は今日の参加公演だけ (昨日の公演には紐づけない)。
        let showId = record.flatMap { streetpassShowCandidate(today: JSTDay.today(), myAttended: $0.attended) }
        let infos = (try? await AppContainer.shared.producerCards.showInfos(ids: [showId].compactMap { $0 })) ?? [:]
        do {
            // 画面が無いので同じ人か確かめる名刺は聞けない。確かめずに別の名刺として足す。
            let saved = try await ProducerCardInbox.store(
                payload: payload, images: [], source: .app, via: .streetPass,
                show: showId.flatMap { infos[$0] }, choice: .separate)
            await refreshTodayCount()
            guard streetpassShouldNotice(before: before, after: todayCount),
                  UIApplication.shared.applicationState != .active else { return }
            await NotificationService.shared.postNow(
                identifier: "streetpass-\(saved.id)",
                body: streetpassNoticeText(name: saved.card?.name ?? ""))
        } catch {
            logger.error("streetpass_store_failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 無線

    private func startRadios() {
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(
                delegate: self, queue: nil,
                options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.peripheralRestoreId])
        }
        if centralManager == nil {
            centralManager = CBCentralManager(
                delegate: self, queue: nil,
                options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreId])
        }
        if isOn { startTicking() }
        updateRadio()
    }

    private func stopRadios() {
        tickTask?.cancel()
        tickTask = nil
        if let current {
            current.timeout.cancel()
            centralManager?.cancelPeripheralConnection(current.peripheral)
        }
        current = nil
        queue.removeAll()
        found = [:]
        if let centralManager, centralManager.state == .poweredOn { centralManager.stopScan() }
        if let peripheralManager, peripheralManager.state == .poweredOn {
            peripheralManager.stopAdvertising()
            peripheralManager.removeAllServices()
        }
        // 止めた後に届く古い通知は捨てる (代理を外し、届いても `isCurrent` で弾く)。
        centralManager?.delegate = nil
        peripheralManager?.delegate = nil
        centralManager = nil
        peripheralManager = nil
        serviceAdded = false
        advertiseFailed = false
        haltingRestored = false
        radio = .unknown
    }

    /// 期限切れで起こされたとき。状態が分かった manager から名乗り・スキャンを止め、両方済んだら手放す。
    private func haltRestored() {
        let states = [centralManager?.state, peripheralManager?.state].compactMap { $0 }
        guard !states.contains(.unknown), !states.contains(.resetting) else { return }
        stopRadios()
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Int(Self.tuning.tickSeconds)))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard checkExpiry() else { return }
        queue.prune(now: Date())
        recent = streetpassPruneSeen(recent: recent, now: Self.now())
        // 日付の変わり目の今日の人数と、名乗る名刺 (担当・参加の記録) を読み直す。
        Task { await refresh() }
        // 一度見つけた相手は同じスキャンの間はもう届かないので、掛け直して離れて戻った人も見つける。
        if current == nil, let centralManager, centralManager.state == .poweredOn {
            centralManager.stopScan()
            scan(centralManager)
        }
    }

    /// オンのままか。時間を過ぎていればここでオフにする。
    @discardableResult
    private func checkExpiry() -> Bool {
        guard isOn else { return false }
        if streetpassIsActive(startedAt: Self.storedStartedAt, now: Self.now()) { return true }
        turnOff()
        return false
    }

    private func updateRadio() {
        let states = [centralManager?.state, peripheralManager?.state].compactMap { $0 }
        if states.contains(.unauthorized) || [.denied, .restricted].contains(CBManager.authorization) {
            radio = .unauthorized
        } else if states.contains(.unsupported) {
            radio = .unsupported
        } else if states.contains(.poweredOff) {
            radio = .poweredOff
        } else if advertiseFailed {
            radio = .advertiseFailed
        } else if !states.isEmpty, states.allSatisfy({ $0 == .poweredOn }) {
            radio = .ready
        } else {
            radio = .unknown
        }
    }

    // MARK: - 名乗る (peripheral)

    private func advertise(_ manager: CBPeripheralManager) {
        guard manager.state == .poweredOn else { return }
        guard frames != nil else {
            // 名乗れない名刺 (欠片に収まらない等)。探して読むのは続ける。
            if manager.isAdvertising { manager.stopAdvertising() }
            return
        }
        if !serviceAdded {
            let characteristics = ([headerUUID] + chunkUUIDs).map {
                CBMutableCharacteristic(type: $0, properties: [.read], value: nil, permissions: [.readable])
            }
            let service = CBMutableService(type: serviceUUID, primary: true)
            service.characteristics = characteristics
            // 復元で前の起動のサービスが残っていることがあるので、足す前に外す。
            manager.removeAllServices()
            manager.add(service)
            serviceAdded = true
            return  // 足し終えたら (didAdd) 広告を始める。
        }
        if !manager.isAdvertising {
            // 名前は載せない (端末名を出さない)。
            manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID]])
        }
    }

    private func value(for uuid: CBUUID) -> Data? {
        guard let frames else { return nil }
        if uuid == headerUUID { return frames.header }
        if let index = chunkUUIDs.firstIndex(of: uuid), index < frames.chunks.count { return frames.chunks[index] }
        return nil
    }

    private func respond(to request: CBATTRequest, on manager: CBPeripheralManager) {
        // 自動オフの時間を過ぎていたら読ませずに止める (裏で起こされて答えている間に過ぎることがある)。
        guard checkExpiry() else {
            manager.respond(to: request, withResult: .readNotPermitted)
            return
        }
        guard manager === peripheralManager, let value = value(for: request.characteristic.uuid) else {
            manager.respond(to: request, withResult: .attributeNotFound)
            return
        }
        // 読む側は長い値を offset 付きで分けて読む。
        guard request.offset <= value.count else {
            manager.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = Data(value.dropFirst(request.offset))
        manager.respond(to: request, withResult: .success)
    }

    // MARK: - 探して読む (central)

    private func scan(_ manager: CBCentralManager) {
        guard manager.state == .poweredOn else { return }
        // 裏ではサービスを指定したスキャンしか届かないので、必ず指定する。
        manager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    private func discovered(_ peripheral: CBPeripheral) {
        guard checkExpiry(), streetpassAccepts(todayCount: todayCount) else { return }
        let id = peripheral.identifier
        guard current?.peripheral.identifier != id, queue.offer(id, now: Date()) else { return }
        found[id] = peripheral
        connectNext()
    }

    /// 待ち行列の先頭に繋ぐ (同時に 1 台ずつ)。
    private func connectNext() {
        guard current == nil, let centralManager, centralManager.state == .poweredOn else { return }
        let next = queue.next(now: Date())
        let peripheral = next.flatMap { found.removeValue(forKey: $0) }
        // 待ち行列から捨てられた相手は手放す。
        found = found.filter { queue.contains($0.key) }
        guard let id = next, let peripheral else { return }
        peripheral.delegate = self
        // connect は自分では時間切れにならないので、待ちを過ぎたら必ず切る。
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Int(Self.tuning.connectTimeoutSeconds)))
            guard !Task.isCancelled else { return }
            self?.finish(id, reason: "timeout")
        }
        current = Reading(peripheral: peripheral, timeout: timeout)
        centralManager.connect(peripheral, options: nil)
    }

    /// 今の相手を切って次へ。`reason` が nil なら読めた (既に読んだ人も含む)、あれば失敗 (記録だけ)。
    private func finish(_ id: UUID, reason: String?) {
        guard let reading = current, reading.peripheral.identifier == id else { return }
        reading.timeout.cancel()
        current = nil
        if let reason {
            logger.info("streetpass_peer_end: \(reason, privacy: .public)")
            queue.markFailed(id, now: Date())
        } else {
            queue.markRead(id, now: Date())
        }
        centralManager?.cancelPeripheralConnection(reading.peripheral)
        connectNext()
    }

    private func isCurrent(_ peripheral: CBPeripheral) -> Bool {
        current?.peripheral.identifier == peripheral.identifier
    }

    private func connected(_ peripheral: CBPeripheral) {
        guard isCurrent(peripheral) else { return }
        peripheral.discoverServices([serviceUUID])
    }

    private func discoveredServices(_ peripheral: CBPeripheral, error: (any Error)?) {
        guard isCurrent(peripheral) else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            finish(peripheral.identifier, reason: "no_service")
            return
        }
        peripheral.discoverCharacteristics([headerUUID] + chunkUUIDs, for: service)
    }

    private func discoveredCharacteristics(_ peripheral: CBPeripheral, service: CBService, error: (any Error)?) {
        guard isCurrent(peripheral) else { return }
        let found = Dictionary((service.characteristics ?? []).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        guard error == nil, let header = found[headerUUID] else {
            finish(peripheral.identifier, reason: "no_header")
            return
        }
        current?.characteristics = found
        peripheral.readValue(for: header)
    }

    private func readValue(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: (any Error)?) {
        guard isCurrent(peripheral), let reading = current else { return }
        let id = peripheral.identifier
        guard error == nil, let value = characteristic.value else {
            finish(id, reason: "read_failed")
            return
        }
        let now = Self.now()
        if characteristic.uuid == headerUUID {
            guard let header = streetpassHeaderDecode(bytes: value) else {
                finish(id, reason: "bad_header")
                return
            }
            guard streetpassShouldRead(fingerprint: header.fingerprint, ownFingerprint: ownFingerprint,
                                       recent: recent, now: now) else {
                finish(id, reason: nil)
                return
            }
            current?.header = header
            readNextChunk(peripheral)
            return
        }
        guard let header = reading.header, reading.chunks.count < chunkUUIDs.count,
              characteristic.uuid == chunkUUIDs[reading.chunks.count] else { return }
        current?.chunks.append(value)
        let chunks = reading.chunks + [value]
        guard chunks.count >= Int(header.chunkCount) else {
            readNextChunk(peripheral)
            return
        }
        guard let payload = streetpassJoin(header: header, chunks: chunks) else {
            finish(id, reason: "bad_chunks")
            return
        }
        recent = streetpassPruneSeen(recent: recent + [StreetpassSeen(fingerprint: header.fingerprint, at: now)], now: now)
        finish(id, reason: nil)
        Task { await receive(payload) }
    }

    private func readNextChunk(_ peripheral: CBPeripheral) {
        guard let reading = current else { return }
        let index = reading.chunks.count
        guard index < chunkUUIDs.count, let characteristic = reading.characteristics[chunkUUIDs[index]] else {
            finish(peripheral.identifier, reason: "no_chunk")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    // MARK: - 保存・日時

    private static var storedStartedAt: String? { UserDefaults.standard.string(forKey: startedAtKey) }

    private static func clearStartedAt() { UserDefaults.standard.removeObject(forKey: startedAtKey) }

    private static func now() -> String { ISO8601DateFormatter.shared.string(from: Date()) }

    /// 端末の DB を (main thread を塞がずに) 開いておく。裏で起こされたときは起動の流れより先に読むことがある。
    private static func ensureDatabase() async -> Bool {
        await Task.detached(priority: .utility) { (try? AppDatabase.prepare()) != nil }.value
    }
}

// MARK: - 代理 (queue: nil なので main queue で届く。MainActor に戻して扱う)

extension StreetPassService: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated {
            guard peripheral === peripheralManager else { return }
            if haltingRestored {
                if peripheral.state == .poweredOn {
                    peripheral.stopAdvertising()
                    peripheral.removeAllServices()
                }
                haltRestored()
                return
            }
            guard checkExpiry() else { return }
            if peripheral.state != .poweredOn { serviceAdded = false }
            updateRadio()
            advertise(peripheral)
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        // 前の起動のサービスは `advertise` が外して足し直す。
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        MainActor.assumeIsolated {
            guard peripheral === peripheralManager else { return }
            if let error {
                logger.error("streetpass_add_service_failed: \(error.localizedDescription)")
                serviceAdded = false
                return
            }
            advertise(peripheral)
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        MainActor.assumeIsolated {
            guard peripheral === peripheralManager else { return }
            if let error { logger.error("streetpass_advertise_failed: \(error.localizedDescription)") }
            advertiseFailed = error != nil
            updateRadio()
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        MainActor.assumeIsolated { respond(to: request, on: peripheral) }
    }
}

extension StreetPassService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            guard central === centralManager else { return }
            if haltingRestored {
                if central.state == .poweredOn { central.stopScan() }
                haltRestored()
                return
            }
            guard checkExpiry() else { return }
            updateRadio()
            if central.state == .poweredOn {
                scan(central)
                connectNext()
            } else if let current {
                finish(current.peripheral.identifier, reason: "radio_off")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // 前の起動で繋いでいた相手は読み途中なので切る (見つけ直して読み直す)。
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in peripherals { central.cancelPeripheralConnection(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard central === centralManager else { return }
            discovered(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard central === centralManager else { return }
            connected(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: (any Error)?) {
        MainActor.assumeIsolated {
            guard central === centralManager else { return }
            finish(peripheral.identifier, reason: "connect_failed")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: (any Error)?) {
        MainActor.assumeIsolated {
            guard central === centralManager else { return }
            finish(peripheral.identifier, reason: "disconnected")
        }
    }
}

extension StreetPassService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        MainActor.assumeIsolated { discoveredServices(peripheral, error: error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: (any Error)?) {
        MainActor.assumeIsolated { discoveredCharacteristics(peripheral, service: service, error: error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: (any Error)?) {
        MainActor.assumeIsolated { readValue(peripheral, characteristic: characteristic, error: error) }
    }
}

extension AppContainer {
    /// すれちがいモード (端末に 1 つ。裏でも動くので画面とは別に持つ)。
    @MainActor var streetPass: StreetPassService { .shared }
}
