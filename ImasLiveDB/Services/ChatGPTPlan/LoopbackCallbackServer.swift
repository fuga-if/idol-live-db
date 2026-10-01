import Foundation
import Network

/// OAuth のリダイレクトを `http://127.0.0.1:<port>/auth/callback` で受ける最小の HTTP サーバ。
///
/// Sign in with ChatGPT はリダイレクト先をループバックに固定している (カスタムスキームも
/// `localhost` も不可)。ブラウザ (ASWebAuthenticationSession / SFSafariViewController) は
/// 別プロセスだが同じ端末なので、アプリが前面にいる間はここで受けられる。
///
/// 1 回の認可で 1 回だけ使う。callback 以外のパス (favicon 等) には 404 を返して待ち続ける。
final class LoopbackCallbackServer: @unchecked Sendable {
    static let callbackPath = "/auth/callback"

    enum ServerError: LocalizedError {
        case listenerFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .listenerFailed(let detail): "127.0.0.1 で待ち受けできませんでした: \(detail)"
            case .cancelled: "待ち受けを止めました"
            }
        }
    }

    let port: UInt16
    var redirectURI: String { "http://127.0.0.1:\(port)\(Self.callbackPath)" }

    private let queue = DispatchQueue(label: "chatgpt-plan.loopback")
    private var listener: NWListener?
    // 以下は queue 上でだけ触る。
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<URLComponents, Error>?
    private var receivedCallback: URLComponents?
    private var finished = false

    init(port: UInt16 = 1455) {
        self.port = port
    }

    /// 待ち受けを開始し、ready になるまで待つ。ブラウザを開くのはこの後。
    func start() async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: params)
        self.listener = listener
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                self.readyContinuation = cont
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handleListenerState(state)
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: self.queue)
            }
        }
    }

    /// `/auth/callback` へのリクエストが来るまで待ち、そのクエリを返す。
    func waitForCallback() async throws -> URLComponents {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                if let received = self.receivedCallback {
                    cont.resume(returning: received)
                } else if self.finished {
                    cont.resume(throwing: ServerError.cancelled)
                } else {
                    self.callbackContinuation = cont
                }
            }
        }
    }

    func stop() {
        queue.async {
            self.finished = true
            self.listener?.cancel()
            self.listener = nil
            self.callbackContinuation?.resume(throwing: ServerError.cancelled)
            self.callbackContinuation = nil
            self.readyContinuation?.resume(throwing: ServerError.cancelled)
            self.readyContinuation = nil
        }
    }

    // MARK: - queue 上

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            readyContinuation?.resume()
            readyContinuation = nil
        case .failed(let error):
            readyContinuation?.resume(throwing: ServerError.listenerFailed(error.localizedDescription))
            readyContinuation = nil
            callbackContinuation?.resume(throwing: ServerError.listenerFailed(error.localizedDescription))
            callbackContinuation = nil
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8))
            if headerEnd == nil, !isComplete, error == nil, buffer.count < 64 * 1024 {
                self.receiveRequest(on: connection, buffer: buffer)
                return
            }
            self.respond(to: buffer, on: connection)
        }
    }

    private func respond(to request: Data, on connection: NWConnection) {
        // リクエスト行: "GET /auth/callback?code=...&state=... HTTP/1.1"
        let firstLine = String(decoding: request.prefix(while: { $0 != 0x0D && $0 != 0x0A }), as: UTF8.self)
        let parts = firstLine.split(separator: " ")
        let target = parts.count >= 2 ? String(parts[1]) : ""
        let components = URLComponents(string: "http://127.0.0.1:\(port)\(target)")

        guard parts.first == "GET", let components, components.path == Self.callbackPath else {
            send(status: "404 Not Found", body: "Not Found", on: connection)
            return
        }

        let isError = components.queryItems?.contains { $0.name == "error" } ?? false
        let html = """
        <!doctype html><html lang="ja"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>アイドルライブDB</title>
        <style>body{font-family:-apple-system,sans-serif;display:flex;min-height:90vh;align-items:center;justify-content:center;text-align:center;color:#1c1c1e}
        @media (prefers-color-scheme:dark){body{background:#000;color:#fff}}</style></head>
        <body><div><p style="font-size:20px;font-weight:600">\(isError ? "連携は完了しませんでした" : "ChatGPT との連携を受け取りました")</p>
        <p>アプリに戻ります。この画面は閉じて大丈夫です。</p></div></body></html>
        """
        send(status: "200 OK", body: html, contentType: "text/html; charset=utf-8", on: connection)

        if receivedCallback == nil {
            receivedCallback = components
            callbackContinuation?.resume(returning: components)
            callbackContinuation = nil
        }
    }

    private func send(status: String, body: String, contentType: String = "text/plain; charset=utf-8", on connection: NWConnection) {
        let bodyData = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bodyData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
