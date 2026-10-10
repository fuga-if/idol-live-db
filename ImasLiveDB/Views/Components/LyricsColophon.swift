import SwiftUI

/// 歌詞の末尾の奥付と、報告・モデレーターの操作。
///
/// - 歌詞入力: 投稿で公開した人 (名前は本人が載せると選んだ人だけ。並びと「ほか N 人」はコア `lyricsCreditLine`)。
/// - この歌詞を報告: 転載・誤り・削除の求めを運営に送る (本文は送らない)。
/// - モデレーター: 非公開 ⇄ 公開、投稿で上書きされる前の版に戻す。どれも本文は消さない。
struct LyricsColophon: View {
    let songId: String
    let credit: LyricsCredit?
    let isDraft: Bool
    /// 公開状態や版を変えたあとに歌詞を取り直す。
    let onChanged: () async -> Void

    @State private var showReportReasons = false
    @State private var reportSent = false
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var creditLine: ShowCreditLine? {
        guard let credit else { return nil }
        return lyricsCreditLine(input: ShowCreditInput(names: credit.names, total: UInt32(max(credit.total, 0))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            if let line = creditLine {
                ImasCardList {
                    ImasValueRow(key: "歌詞入力", value: Self.names(line))
                }
            }
            ImasCardList {
                ImasActionRow(title: "この歌詞を報告", systemImage: "flag") {
                    AppAnalytics.tap("lyrics.report")
                    showReportReasons = true
                }
                .disabled(!AuthService.shared.isSignedIn || isWorking)
                if AuthService.shared.adminCapabilities.canEditLyrics {
                    ImasActionRow(title: isDraft ? "公開する" : "非公開にする",
                                  systemImage: isDraft ? "eye" : "eye.slash",
                                  kind: isDraft ? .standard : .destructive) {
                        Task { await run { try await LyricsModerationAPI.shared.setPublished(songId: songId, isDraft) } }
                    }
                    .disabled(isWorking)
                    ImasActionRow(title: "1 つ前の版に戻す", systemImage: "arrow.uturn.backward") {
                        Task { await run { try await LyricsModerationAPI.shared.restorePrevious(songId: songId) } }
                    }
                    .disabled(isWorking)
                }
            }
            ImasNote("歌詞サイトや他のサービスから写した歌詞は、公開後でも削除します。")
        }
        .confirmationDialog("この歌詞を報告", isPresented: $showReportReasons, titleVisibility: .visible) {
            ForEach(LyricsModerationAPI.ReportReason.allCases, id: \.self) { reason in
                Button(reason.label) {
                    Task { await run { try await LyricsModerationAPI.shared.report(songId: songId, reason: reason) }
                           if errorMessage == nil { reportSent = true } }
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("運営が確認し、必要なら非公開にします。")
        }
        .alert("報告を送りました", isPresented: $reportSent) {
            Button("OK") {}
        } message: {
            Text("ありがとうございます。運営が確認します。")
        }
        .imasErrorAlert("送れませんでした", message: $errorMessage)
    }

    /// 送って、成功したら歌詞を取り直す (報告は表示が変わらないが、取り直しても害はない)。
    private func run(_ action: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await action()
            await onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 「A・B ほか 2 人」。名前を載せる人がいなければ「3 人」。
    private static func names(_ line: ShowCreditLine) -> String {
        let names = line.names.joined(separator: "・")
        if line.unnamedCount == 0 { return names }
        return names.isEmpty ? "\(line.unnamedCount) 人" : "\(names) ほか \(line.unnamedCount) 人"
    }
}
