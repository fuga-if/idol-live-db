@preconcurrency import MultipeerConnectivity
import Foundation
import os
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "nearby_card")

/// 近くの iPhone どうしで名刺ファイル (名刺 + 担当の画像) を直接渡す。圏外の会場でも届く。
///
/// - 見せている側 (`startShowing`) は、自分の名刺の札 (`cardPeerTag`) を名乗って待つ。
///   招待は**合言葉 (`cardInviteProof`) が自分の名刺と一致したときだけ**受ける。合言葉は QR を
///   読んだ人にしか作れないので、QR を見ずに近くで名刺を集めたり、勝手に名刺を入れたりできない。
/// - 読んだ側 (`startReading`) は、読み取った名刺から札と合言葉を作って相手を探し、繋ぐ。
/// - 繋がったら**お互いに自分の名刺ファイルを送る** (1 回のスキャンで双方向の交換になる)。
///   読んだ側は受け取りの確認で ✓ を押してから送る (`allowSending`。× でやめたら渡さない)。
///   読んだ側が名刺を作っていなければ送らない (片方向)。
///
/// Android とは繋がらない (QR だけで成立する。画像は名刺ファイルを共有で送ってもらう)。
/// 見せている画面を閉じたら `stop()` で名乗りをやめる。
@MainActor @Observable
final class NearbyCardExchange: NSObject {
    enum Phase: Equatable {
        case idle
        /// 名乗って待っている (見せている側)。
        case waiting
        /// 相手を探している (読んだ側)。
        case searching
        case connected
        /// 相手の名刺ファイルが届いた。
        case received
        /// 相手が近くに見つからなかった・途中で切れた (読んだ側)。
        case notFound
    }

    static let serviceType = "imascard"
    nonisolated private static let tagKey = "t"
    /// 読んだ側が相手を探し、届くのを待つ時間。過ぎたら「見つからない」にする
    /// (QR の中身だけで保存はできる)。
    private static let searchTimeout: Duration = .seconds(15)

    private(set) var phase: Phase = .idle
    /// 届いた名刺ファイル。
    private(set) var received: CardFileContents?
    /// 名刺ファイルが届いたとき。
    var onReceive: ((CardFileContents) -> Void)?

    /// 招待は任意のスレッドから届き、その場で返事が要る。受ける session と合言葉はロックの中で持つ
    /// (書くのは MainActor の start/stop、読むのは代理のスレッド)。
    private struct Accepting {
        var session: MCSession?
        var proof: Data?
    }
    @ObservationIgnored nonisolated private let accepting = OSAllocatedUnfairLock(uncheckedState: Accepting())

    @ObservationIgnored private let peerID = MCPeerID(displayName: "P名刺")
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var outgoing: Data?
    @ObservationIgnored private var targetTag: String?
    @ObservationIgnored private var inviteProof: Data?
    @ObservationIgnored private var invited: Set<MCPeerID> = []
    @ObservationIgnored private var connected: Set<MCPeerID> = []
    /// 自分の名刺を送ってよいか (見せている側は最初から、読んだ側は ✓ の後)。
    @ObservationIgnored private var sendAllowed = false
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    /// 読んだ側として、まだ相手を探している・届くのを待っている。
    var isWaitingForPeer: Bool { phase == .searching || phase == .connected }

    /// 見せている側。自分の名刺ファイルを持って名乗る。
    func startShowing(payload: String, file: Data) {
        stop()
        outgoing = file
        sendAllowed = true
        let session = makeSession()
        let proof = Data(cardInviteProof(payload: payload).utf8)
        accepting.withLockUnchecked { $0 = Accepting(session: session, proof: proof) }
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID, discoveryInfo: [Self.tagKey: cardPeerTag(payload: payload)],
            serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.session = session
        self.advertiser = advertiser
        phase = .waiting
    }

    /// 読んだ側。読み取った名刺の相手を探す。`file` は送り返す自分の名刺ファイル (無ければ片方向)。
    func startReading(payload: String, file: Data?) {
        stop()
        outgoing = file
        targetTag = cardPeerTag(payload: payload)
        inviteProof = Data(cardInviteProof(payload: payload).utf8)
        session = makeSession()
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        phase = .searching
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchTimeout)
            guard let self, !Task.isCancelled, self.isWaitingForPeer else { return }
            self.phase = .notFound
            self.browser?.stopBrowsingForPeers()
        }
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        accepting.withLockUnchecked { $0 = Accepting() }
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        outgoing = nil
        targetTag = nil
        inviteProof = nil
        invited = []
        connected = []
        sendAllowed = false
        received = nil
        phase = .idle
    }

    /// 読んだ側が ✓ を押した。繋がっている相手 (と、これから繋がる相手) に自分の名刺を送る。
    func allowSending() {
        guard !sendAllowed else { return }
        sendAllowed = true
        for peer in connected { send(to: peer) }
    }

    private func send(to peer: MCPeerID) {
        guard sendAllowed, let outgoing, let session else { return }
        do {
            try session.send(outgoing, toPeers: [peer], with: .reliable)
        } catch {
            logger.error("nearby_card_send_failed: \(error.localizedDescription)")
        }
    }

    private func makeSession() -> MCSession {
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }

    /// 通知が今の session から来たか (止めた後に古い session から届いたものは捨てる)。
    private func isCurrent(_ id: ObjectIdentifier) -> Bool {
        session.map(ObjectIdentifier.init) == id
    }

    // MARK: - 届いたもの (MainActor)

    private func peerConnected(_ peer: MCPeerID, in sessionId: ObjectIdentifier) {
        guard isCurrent(sessionId) else { return }
        connected.insert(peer)
        if phase != .received && phase != .waiting { phase = .connected }
        browser?.stopBrowsingForPeers()
        send(to: peer)
    }

    private func peerDisconnected(_ peer: MCPeerID, in sessionId: ObjectIdentifier) {
        guard isCurrent(sessionId) else { return }
        connected.remove(peer)
        guard browser != nil else { return }
        invited.remove(peer)
        switch phase {
        case .searching:
            // 招待が断られた・待ち切れた。探し続けて、次に見つけたらもう一度招く。
            browser?.startBrowsingForPeers()
        case .connected:
            // 届く前に切れた (相手が画面を閉じた等)。
            phase = .notFound
        default:
            break
        }
    }

    private func dataReceived(_ data: Data, in sessionId: ObjectIdentifier) {
        guard isCurrent(sessionId) else { return }
        guard let contents = decodeCardFile(bytes: data) else {
            logger.error("nearby_card_unreadable bytes=\(data.count)")
            return
        }
        received = contents
        if phase != .waiting { phase = .received }
        timeoutTask?.cancel()
        onReceive?(contents)
    }

    private func peerFound(_ peer: MCPeerID, tag: String?) {
        guard let targetTag, tag == targetTag, let session, let browser, !invited.contains(peer) else { return }
        invited.insert(peer)
        browser.invitePeer(peer, to: session, withContext: inviteProof, timeout: 10)
    }
}

// MARK: - 代理 (MultipeerConnectivity は任意のスレッドから呼ぶ)

extension NearbyCardExchange: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let id = ObjectIdentifier(session)
        switch state {
        case .connected:
            Task { @MainActor in self.peerConnected(peerID, in: id) }
        case .notConnected:
            Task { @MainActor in self.peerDisconnected(peerID, in: id) }
        default:
            break
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let id = ObjectIdentifier(session)
        Task { @MainActor in self.dataReceived(data, in: id) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String,
                             fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
}

extension NearbyCardExchange: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // 合言葉が自分の名刺と一致した相手 (= QR を読んだ人) だけを受ける。読み取りと返事をロックの中で
        // 行い、止めている最中の session を掴まない。
        accepting.withLockUnchecked { state in
            guard let session = state.session, let proof = state.proof, context == proof else {
                invitationHandler(false, nil)
                return
            }
            invitationHandler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        logger.error("nearby_card_advertise_failed: \(error.localizedDescription)")
    }
}

extension NearbyCardExchange: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        let tag = info?[Self.tagKey]
        Task { @MainActor in self.peerFound(peerID, tag: tag) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        logger.error("nearby_card_browse_failed: \(error.localizedDescription)")
        Task { @MainActor in if self.phase == .searching { self.phase = .notFound } }
    }
}
