import os
import PhotosUI
import SwiftUI

/// コール表の画像から、歌詞とコールの下書きを作るシート。
///
/// 画像を利用者の ChatGPT プランに送って書き写してもらう (`CallSheetRunner`)。できるのは下書きまでで、
/// 歌詞は投稿画面、コールは編集画面に入れ、本人が確かめてから送る。ここからは何も保存しない。
/// 読んだ中身の検証・歌詞への当て方はコア (`domain::call_guide_import`)。
struct CallSheetImportSheet: View {
    let song: Song
    /// 歌詞がもうある曲か。あればコールの編集へ、無ければ歌詞の投稿へ入れる。
    let hasLyrics: Bool
    /// 下書きを使うと決めた (閉じたあと、呼び出し側が投稿画面か編集に入れる)。
    let onUse: (CallSheetReading) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picks: [PhotosPickerItem] = []
    @State private var progress: String?
    @State private var reading: CallSheetReading?
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @State private var runID: UUID?

    private var session: ChatGPTPlanSession { .shared }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                if let reading {
                    result(reading)
                } else {
                    intro
                }
            }
            .navigationTitle("コール表から下書き")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .onChange(of: picks) { _, new in
                guard !new.isEmpty else { return }
                start(new)
            }
            .imasErrorAlert("読み取れませんでした", message: $errorMessage)
        }
        .onDisappear { task?.cancel() }
        .trackScreen("call_sheet_import")
    }

    // MARK: - 読む前

    @ViewBuilder
    private var intro: some View {
        ImasNote("コール表の画像を ChatGPT に書き写してもらい、\(hasLyrics ? "コール" : "歌詞とコール")の下書きを作ります。できるのは下書きまでで、送る前にあなたが確かめます。",
                 systemImage: "text.viewfinder")
        if !session.canUsePlan {
            ImasNote("マイページで ChatGPT とつなぐと使えます。", systemImage: "link")
        } else if let progress {
            VStack(spacing: DS.Space.gap) {
                ImasInlineLoading(tint: DS.sys)
                Text(progress).imasText(.note)
                ImasButton(title: "やめる", systemImage: "xmark", role: .secondary, size: .small) { cancel() }
            }
            .frame(maxWidth: .infinity)
        } else {
            PhotosPicker(selection: $picks, maxSelectionCount: Int(callSheetMaxImages()), matching: .images) {
                Label("画像を選ぶ", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.imas(.primary, fillsWidth: true))
        }
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            caution("選んだ画像は、あなたの ChatGPT のアカウントに送られます。")
            caution("自分で作ったコール表か、作った人が使ってよいと言っているものだけを選んでください。")
            if !hasLyrics {
                caution("歌詞は、歌詞カードと見比べて直してから投稿してください (投稿ガイドラインは変わりません)。")
            }
        }
    }

    private func caution(_ text: String) -> some View {
        Text(text)
            .font(.imasFootnote)
            .foregroundStyle(DS.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 読んだあと

    @ViewBuilder
    private func result(_ reading: CallSheetReading) -> some View {
        ImasNote("歌詞 \(reading.lines.count) 行・コール \(reading.callCount) 件を読みました。", systemImage: "checkmark")
        if !reading.ocrChecked {
            ImasNotice(kind: .warning, message: "端末の文字認識で字を拾えなかったので、読んだ中身を確かめられていません。\(hasLyrics ? "画像と見比べてください。" : "")")
        } else if reading.doubtfulLines > 0 {
            ImasNotice(kind: .warning, message: "印の付いた \(reading.doubtfulLines) 行は、端末の文字認識で同じ字を確かめられませんでした。\(hasLyrics ? "画像に無い字が混ざっているかもしれません。" : "歌詞の下書きには入れません。")")
        }
        // 歌詞の下書きに入るのは、文字認識で同じ字を確かめられた行だけ (何行かはコアが決める)。
        let usable = Int(callSheetLyricLineCount(reading: reading))
        if hasLyrics || usable > 0 {
            ImasButton(title: hasLyrics ? "コールの編集に入れる" : "歌詞の投稿に入れる",
                       systemImage: hasLyrics ? "square.and.pencil" : "text.quote",
                       role: .primary, size: .large, fillsWidth: true) {
                AppAnalytics.tap(hasLyrics ? "call_sheet.use_calls" : "call_sheet.use_lyrics")
                onUse(reading)
                dismiss()
            }
            if !hasLyrics, usable < reading.lines.count {
                caution("確かめられた \(usable) 行だけを入れます。残りは歌詞カードを見て足してください。")
            }
        } else {
            caution("確かめられた行が無いので、歌詞の下書きは作れません。字がはっきり写った画像で試してください。")
        }
        if !hasLyrics {
            caution("コールは、歌詞が公開されたあと「コールを付ける」から入れられます (アプリを閉じるまで覚えています)。")
        }
        ImasButton(title: "別の画像で読み直す", systemImage: "arrow.counterclockwise", role: .secondary, size: .small) {
            self.reading = nil
        }
        ImasSection("読んだ中身", style: .small) {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                ForEach(Array(reading.lines.enumerated()), id: \.offset) { _, line in
                    lineRow(line).padding(.top, line.breakBefore ? DS.Space.gap : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func lineRow(_ line: SheetLine) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.gapTight) {
                if line.doubtful {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.imasFootnote)
                        .foregroundStyle(DS.danger)
                        .accessibilityLabel("確かめられなかった行")
                }
                Text(line.lyric).fixedSize(horizontal: false, vertical: true)
            }
            if !line.calls.isEmpty {
                Text(line.calls.map(\.text).joined(separator: " / "))
                    .font(.imasFootnote.weight(.semibold))
                    .foregroundStyle(DS.sys)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 読む

    private func start(_ items: [PhotosPickerItem]) {
        guard session.canUsePlan, progress == nil else { return }
        AppAnalytics.tap("call_sheet.read")
        progress = "画像を開いています…"
        let id = UUID()
        runID = id
        task = Task {
            defer { if runID == id { progress = nil; picks = [] } }
            do {
                let images = await LyricsCardOCR.images(from: items)
                guard !images.isEmpty else {
                    throw ChatGPTPlanTaskRunner.RunnerError(message: "画像を開けませんでした")
                }
                let read = try await CallSheetRunner.read(images: images) { label in
                    if runID == id { progress = label }
                }
                if Task.isCancelled || runID != id { return }
                reading = read
            } catch is CancellationError {
                // やめた。
            } catch {
                if Task.isCancelled || runID != id { return }
                Logger.database.error("call_sheet_read_failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancel() {
        task?.cancel()
        task = nil
        runID = nil
        progress = nil
        picks = []
    }
}
