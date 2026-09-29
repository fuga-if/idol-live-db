import SwiftUI
import UIKit

/// 遊んだ曲のジャケットを斜めのモザイクにして敷く背景 (曲のゲームのシェア画像 `QuizShareCard` が使う)。
/// ジャケットが無ければアプリアイコンのペンライト帯の色のタイルで代用する。
struct LyricsQuizMosaicBackground: View {
    let images: [UIImage]

    private static let tile: CGFloat = 250
    private static let gap: CGFloat = 14
    private static let columns = 8
    private static let rows = 9
    /// ジャケットが無いときの代わり (アプリアイコンのペンライト帯の色)。
    private static let fallback: [Color] = [
        Color(red: 0.93, green: 0.13, blue: 0.16), Color(red: 0.95, green: 0.60, blue: 0.10),
        Color(red: 0.98, green: 0.76, blue: 0.10), Color(red: 0.10, green: 0.74, blue: 0.56),
        Color(red: 0.42, green: 0.71, blue: 0.73), Color(red: 0.15, green: 0.50, blue: 0.80),
        Color(red: 0.38, green: 0.41, blue: 0.46),
    ]

    var body: some View {
        // overlay はキャンバスの大きさで置かれるので、はみ出したモザイクもキャンバスで切れる
        Color.black
            .overlay {
                VStack(spacing: Self.gap) {
                    ForEach(0..<Self.rows, id: \.self) { r in
                        HStack(spacing: Self.gap) {
                            ForEach(0..<Self.columns, id: \.self) { c in
                                tile(index: r * Self.columns + c + r * 3)
                            }
                        }
                        // 段ごとに半タイルずらして、同じジャケットが縦に揃わないようにする
                        .offset(x: r.isMultiple(of: 2) ? 0 : (Self.tile + Self.gap) / 2)
                    }
                }
                .fixedSize()
                .rotationEffect(.degrees(-14))
                .opacity(images.isEmpty ? 0.55 : 0.95)
            }
            .overlay {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .black.opacity(0.15), location: 0.18),
                    .init(color: .black.opacity(0.62), location: 0.42),
                    .init(color: .black.opacity(0.9), location: 0.7),
                    .init(color: .black.opacity(0.96), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
        .clipped()
    }

    @ViewBuilder
    private func tile(index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if images.isEmpty {
            shape.fill(Self.fallback[index % Self.fallback.count])
                .frame(width: Self.tile, height: Self.tile)
        } else {
            Image(uiImage: images[index % images.count]).resizable().scaledToFill()
                .frame(width: Self.tile, height: Self.tile)
                .clipShape(shape)
        }
    }
}

/// シェア画像に焼くジャケットの事前ロード。結果画面が出た時点で始めておき、
/// シェアボタンが押されたら (待つとしても最大 `timeout` まで) それを使う。
enum LyricsQuizShareArtwork {
    static func load(_ urls: [String], timeout: Duration = .seconds(4)) async -> [String: UIImage] {
        await withTaskGroup(of: (String, UIImage?)?.self) { group in
            for url in urls {
                group.addTask { (url, await ShareCardArtwork.load(from: url)) }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            var loaded: [String: UIImage] = [:]
            var remaining = urls.count
            while remaining > 0, let next = await group.next() {
                guard let pair = next else { break }  // 時間切れ。取れた分だけで焼く
                remaining -= 1
                if let image = pair.1 { loaded[pair.0] = image }
            }
            group.cancelAll()
            return loaded
        }
    }
}
