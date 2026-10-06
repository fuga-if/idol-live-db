import SwiftUI
@preconcurrency import VisionKit

/// カメラに映った歌詞の行を押した順に 1 行ずつ集めるスキャン画面。
///
/// 読み取りは VisionKit の DataScanner (「テキストをスキャン」と同じ端末内の読み取り)。
/// テキストスキャンは塊の中の改行を落とすことがあるので、こちらは行ごとに押してもらい、
/// 押した順に 1 行ずつ改行で並べる。画像はどこにも送らず、保存もしない。
struct LyricLineScannerView: View {
    /// 集めた行 (押した順)。完了で渡す。
    let onFinish: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            LyricLineScannerCamera { line in
                withAnimation(.imasStandard) { lines.append(line) }
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) { tray }
            .navigationTitle("行を押した順に入ります")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.select(canFinish: !lines.isEmpty,
                                      onCancel: { dismiss() },
                                      onFinish: { onFinish(lines); dismiss() }))
        }
        .trackScreen("lyric_line_scanner")
    }

    /// 集めた行の確認と、最後の 1 行の取り消し。
    private var tray: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            HStack {
                Text(lines.isEmpty ? "歌詞の行を上から順に押してください" : "\(lines.count) 行")
                    .font(.imasFootnote.weight(.semibold))
                    .foregroundStyle(DS.ink2)
                Spacer(minLength: DS.Space.gap)
                if !lines.isEmpty {
                    Button("1 行戻す") { withAnimation(.imasStandard) { _ = lines.popLast() } }
                        .buttonStyle(.imas(.plain, size: .small))
                }
            }
            if !lines.isEmpty {
                Text(lines.suffix(3).joined(separator: "\n"))
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

/// DataScanner の本体。押された文字の項目を 1 つずつ返す。
private struct LyricLineScannerCamera: UIViewControllerRepresentable {
    let onTap: (String) -> Void

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
        let onTap: (String) -> Void
        init(onTap: @escaping (String) -> Void) { self.onTap = onTap }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .text(let text) = item else { return }
            // 1 つの項目が何行かを含むときは、その中の改行もそのまま行として使う。
            for line in text.transcript.split(separator: "\n", omittingEmptySubsequences: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { onTap(trimmed) }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
