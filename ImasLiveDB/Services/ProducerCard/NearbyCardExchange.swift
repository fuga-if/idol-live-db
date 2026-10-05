@preconcurrency import MultipeerConnectivity
import Foundation
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "nearby_card")

/// 近くの iPhone どうしで名刺ファイル (名刺 + 担当の画像) を直接渡す。圏外の会場でも届く。
///
/// - 見せている側 (`startShowing`) は、自分の名刺の札 (`cardPeerTag`) を名乗って待つ。
/// - 読んだ側 (`startReading`) は、読み取った名刺から同じ札を作って相手を探し、見つけたら繋ぐ。
/// - 繋がったら**お互いに自分の名刺ファイルを送る** (1 回のスキャンで双方向の交換になる)。
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
        /// 相手が近くに見つからなかった (読んだ側)。
        case notFound
    }

    static let serviceType = "imascard"
    nonisolated private static let tagKey = "t"
    /// 読んだ側が相手を探す時間。過ぎたら「見つからない」にする (QR の中身だけで保存は済んでいる)。
    private static let searchTimeout: Duration = .seconds(12)

    private(set) var phase: Phase = .idle
    /// 届いた名刺ファイル。
    private(set) var received: CardFileContents?
    /// 名刺ファイルが届いたとき。
    var onReceive: ((CardFileContents) -> Void)?

    @ObservationIgnored private let peerID = MCPeerID(displayName: "P名刺")
    @ObservationIgnored private var session: MCSession?
    /// 見せている間に招待を受ける session。招待は任意のスレッドから届き、返事はその場で要るので
    /// MainActor を経由せずに読む (書くのは MainActor の start/stop だけ)。
    @ObservationIgnored nonisolated(unsafe) private var acceptingSession: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var outgoing: Data?
    @ObservationIgnored private var targetTag: String?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    /// 見せている側。自分の名刺ファイルを持って名乗る。
    func startShowing(payload: String, file: Data) {
        stop()
        outgoing = file
        let session = makeSession()
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID, discoveryInfo: [Self.tagKey: cardPeerTag(payload: payload)],
            serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.session = session
        self.acceptingSession = session
        self.advertiser = advertiser
        phase = .waiting
    }

    /// 読んだ側。読み取った名刺の相手を探す。`file` は送り返す自分の名刺ファイル (無ければ片方向)。
    func startReading(payload: String, file: Data?) {
        stop()
        outgoing = file
        targetTag = cardPeerTag(payload: payload)
        session = makeSession()
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        phase = .searching
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchTimeout)
            guard let self, !Task.isCancelled, self.phase == .searching else { return }
            self.phase = .notFound
            self.browser?.stopBrowsingForPeers()
        }
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        acceptingSession = nil
        outgoing = nil
        targetTag = nil
        phase = .idle
    }

    private func makeSession() -> MCSession {
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }

    // MARK: - 届いたもの (MainActor)

    private func peerConnected(_ peer: MCPeerID) {
        phase = phase == .received ? .received : .connected
        timeoutTask?.cancel()
        guard let outgoing, let session else { return }
        do {
            try session.send(outgoing, toPeers: [peer], with: .reliable)
        } catch {
            logger.error("nearby_card_send_failed: \(error.localizedDescription)")
        }
    }

    private func dataReceived(_ data: Data) {
        guard let contents = decodeCardFile(bytes: data) else {
            logger.error("nearby_card_unreadable bytes=\(data.count)")
            return
        }
        received = contents
        phase = .received
        onReceive?(contents)
    }

    private func peerFound(_ peer: MCPeerID, tag: String?) {
        guard let targetTag, tag == targetTag, let session, let browser else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 15)
        browser.stopBrowsingForPeers()
    }

}

// MARK: - 代理 (MultipeerConnectivity は任意のスレッドから呼ぶ)

extension NearbyCardExchange: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard state == .connected else { return }
        Task { @MainActor in self.peerConnected(peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.dataReceived(data) }
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
        // 名乗っているのは名刺を見せている間だけなので、来た相手はそのまま受ける
        // (中身は名刺ファイルとして読めたものしか扱わない)。
        let session = acceptingSession
        invitationHandler(session != nil, session)
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
