import SwiftUI

/// イントロ再生の経過秒をカウントアップ表示するストップウォッチ・ラベル。
/// /dev/intro (本家 IntroQuiz) の PlaybackElapsedLabel を ImasLiveDB に移植。
///
/// 挙動:
/// - 再生中 (isRunning) はカウントアップ
/// - 再生が止まると **その値で固定表示** (消さない)
/// - 「続きから」で再生再開すると、止まった値から **継続して** 累積
/// - `resetToken` が変わると 0 にリセット (「もう一度」 / 次の曲)
///
/// 呼び出し側は phase 分岐で出し入れせず常にツリーに置き、opacity 等で見せ隠しすること
/// (取り外すと @State がリセットされる)。
struct PlaybackElapsedLabel: View {
    /// ラベル見出し ("再生" 等)。
    var title: String = "再生"
    /// 先頭アイコン。
    var systemImage: String = "speaker.wave.2.fill"
    /// 今まさに計測中か。`isPlaying && !isLoading` で渡す想定。
    let isRunning: Bool
    /// 値を 0 に戻すトリガ。 変化した瞬間にリセット (もう一度 / 次の曲で bump)。
    let resetToken: Int
    var font: Font = .imasCaption.weight(.bold)
    var color: Color = DS.ink2

    /// 停止までに積み上がった再生秒数。
    @State private var accumulated: TimeInterval = 0
    /// 現在の再生セグメントの開始時刻 (走行中のみ non-nil)。
    @State private var runStartedAt: Date?

    var body: some View {
        TimelineView(.animation(paused: runStartedAt == nil)) { ctx in
            Label(String(format: "\(title) %.1f秒", displayed(at: ctx.date)), systemImage: systemImage)
                .font(font)
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .onAppear { if isRunning { runStartedAt = Date() } }
        .onChange(of: isRunning) { _, running in
            if running {
                if runStartedAt == nil { runStartedAt = Date() }
            } else {
                freeze()
            }
        }
        .onChange(of: resetToken) { _, _ in
            // 0 にリセット。 isRunning が既に true (= reset 直前に再生が始まってる)
            // なら即座に新しい走行を開始する。runStartedAt = nil 固定にすると、
            // 次の問題で audio.play() が同一フレームで完結して onChange(isRunning) が
            // 発火しないケース (2曲目以降の停止表示) を踏むため、ここで自前で開始する。
            accumulated = 0
            runStartedAt = isRunning ? Date() : nil
        }
    }

    private func displayed(at now: Date) -> TimeInterval {
        accumulated + (runStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// 走行中セグメントを accumulated に畳み込んで停止 (= 値を固定)。
    private func freeze() {
        if let start = runStartedAt {
            accumulated += max(0, Date().timeIntervalSince(start))
            runStartedAt = nil
        }
    }
}
