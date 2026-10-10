import SwiftUI
@preconcurrency import VisionKit

/// カメラに映った歌詞の塊を押した順に集めるスキャン画面。
///
/// 読み取りは VisionKit の DataScanner (「テキストをスキャン」と同じ端末内の読み取り)。
/// 押した塊は、塊の中の行を改行で、塊と塊の間を空行で並べる (テキストスキャンは改行を落とすことがある)。
/// 画像はどこにも送らず、保存もしない。
struct LyricLineScannerView: View {
    /// 集めた本文 (塊の中は改行、塊の間は空行)。完了で渡す。
    let onFinish: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    /// 押した塊 (押した順)。1 つの塊は行の並び。
    @State private var chunks: [[String]] = []

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            LyricLineScannerCamera { chunk in
                withAnimation(.imasStandard) { chunks.append(chunk) }
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) { tray }
            .navigationTitle("歌詞を押した順に入ります")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.select(canFinish: !chunks.isEmpty,
                                      onCancel: { dismiss() },
                                      onFinish: { onFinish(text); dismiss() }))
        }
        .trackScreen("lyric_line_scanner")
    }

    private var text: String { chunks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n") }

    /// 集めた塊の確認と、最後の 1 つの取り消し。
    private var tray: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            HStack {
                Text(chunks.isEmpty ? "歌詞を上から順に押してください" : "\(chunks.count) か所 · \(chunks.joined().count) 行")
                    .font(.imasFootnote.weight(.semibold))
                    .foregroundStyle(DS.ink2)
                Spacer(minLength: DS.Space.gap)
                if !chunks.isEmpty {
                    Button("1 つ戻す") { withAnimation(.imasStandard) { _ = chunks.popLast() } }
                        .buttonStyle(.imas(.plain, size: .small))
                }
            }
            if let last = chunks.last {
                Text(last.suffix(3).joined(separator: "\n"))
                    .font(.imasBody)
                    .foregroundStyle(DS.ink)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.Space.screen)
        .background(DS.surface)
    }
}

/// DataScanner の本体。押された文字の項目を、行の並びにして 1 つずつ返す。
private struct LyricLineScannerCamera: UIViewControllerRepresentable {
    let onTap: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["ja-JP", "en-US"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency DataScannerViewControllerDelegate {
        let onTap: ([String]) -> Void
        init(onTap: @escaping ([String]) -> Void) { self.onTap = onTap }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .text(let text) = item else { return }
            // 項目の中の改行はそのまま行として使う。
            let lines = text.transcript.split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { return }
            onTap(lines)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
