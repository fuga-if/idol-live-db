import SwiftUI
import UIKit

/// イントロドンの結果を「映える画像」でシェアするためのカード + レンダラ。
/// /dev/intro (本家 IntroQuiz) の ShareImage / SoloShareCard の手法を踏襲:
/// ImageRenderer で SwiftUI カードを UIImage 化 → UIActivityViewController で共有。
/// カード下部に本家アプリ「イントロクイズ」のダウンロード導線を載せ、広告も兼ねる。
enum IntroShareImageRenderer {
    @MainActor
    static func render<Content: View>(size: CGSize, @ViewBuilder content: () -> Content) -> UIImage? {
        let renderer = ImageRenderer(content: content().frame(width: size.width, height: size.height))
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }

    @MainActor
    static func share(image: UIImage?, text: String) {
        let items: [Any] = image.map { [$0, text] } ?? [text]
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                    ?? scene.windows.first?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        presenter.present(vc, animated: true)
    }
}

struct IntroShareLine: Identifiable {
    let id = UUID()
    let title: String
    let correct: Bool
}

/// 結果シェアカード (1080×1350)。見出し/大スコア/グレード/メトリクス/曲別内訳 + 本家宣伝。
struct IntroResultShareCard: View {
    let modeLabel: String
    let score: Int
    let total: Int
    let percentage: Int
    let timeText: String?
    let bestCombo: Int
    let lines: [IntroShareLine]

    private static let maxRows = 10
    private var isPerfect: Bool { percentage >= 100 }
    private var grade: (String, Color) {
        switch percentage {
        case 100:   return ("パーフェクト！", ID.accentGold)
        case 80...: return ("すごい！", ID.correct)
        case 60...: return ("なかなか！", ID.accentBlue)
        case 40...: return ("もう少し！", .orange)
        default:    return ("練習あるのみ！", ID.accentPink)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダ
            VStack(spacing: 12) {
                Text("イントロドン")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundColor(ID.t0)
                Text(isPerfect ? "PERFECT" : "RESULT")
                    .font(.system(size: 22, weight: .black))
                    .tracking(8)
                    .foregroundColor(isPerfect ? ID.accentGold : ID.t2)
                Text(modeLabel)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(ID.accentPink)
            }
            .padding(.top, 64)

            Spacer(minLength: 0)

            // 大スコア + グレード
            VStack(spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(score)")
                        .font(.system(size: 130, weight: .black, design: .rounded))
                        .foregroundColor(ID.t0)
                    Text("/ \(total)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(ID.t2)
                }
                Text(grade.0)
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(grade.1)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(grade.1.opacity(0.14))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            // メトリクス行
            HStack(spacing: 0) {
                statItem("正解率", "\(percentage)%")
                if let timeText { divider; statItem("タイム", timeText) }
                if bestCombo >= 2 { divider; statItem("最大コンボ", "×\(bestCombo)") }
            }
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(ID.surfaceDarkCard)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 56)

            // 曲別内訳
            if !lines.isEmpty {
                breakdown
                    .padding(.horizontal, 56)
                    .padding(.top, 24)
            }

            Spacer(minLength: 0)

            footer
                .padding(.top, 28)
                .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                ID.bgDark
                RadialGradient(colors: [ID.accentPink.opacity(0.20), .clear],
                               center: .top, startRadius: 0, endRadius: 720)
            }
        )
    }

    private var divider: some View {
        Rectangle().fill(ID.t3.opacity(0.25)).frame(width: 1, height: 56)
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundColor(ID.t0)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(ID.t2)
        }
        .frame(maxWidth: .infinity)
    }

    private var breakdown: some View {
        let shown = Array(lines.prefix(Self.maxRows))
        let extra = lines.count - shown.count
        return VStack(spacing: 12) {
            ForEach(shown) { line in
                HStack(spacing: 16) {
                    Image(systemName: line.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(line.correct ? ID.correct : ID.t3)
                    Text(line.title)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(ID.t1)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if extra > 0 {
                Text("ほか \(extra)曲")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(ID.t2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .background(ID.surfaceDarkCard)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("もっと遊ぶなら 本家アプリ")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(ID.t2)
            Text("App Storeで「イントロクイズ」")
                .font(.system(size: 34, weight: .black))
                .foregroundColor(ID.t0)
        }
    }
}
