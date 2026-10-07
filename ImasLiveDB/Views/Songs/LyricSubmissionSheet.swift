import os
import SwiftUI

/// 歌詞を投稿するシート。CD の歌詞カードなどの一次ソースを見て入力した歌詞を送る。
///
/// 歌詞の無い曲なら送るとすぐ公開され、運営があとから確認する (`LyricSubmissionAPI`)。
/// 投稿ガイドラインに同意しないと送れない。入力元は書かせない (規約で縛る)。
/// 本文の整え方・上限・注意はコア (`lyricSubmissionCheck`) が決める。
struct LyricSubmissionSheet: View {
    let song: Song

    @Environment(\.dismiss) private var dismiss

    /// 入力は `LyricSubmissionDrafts` に置く (画面が組み直されても消えないように)。
    @State private var drafts = LyricSubmissionDrafts.shared
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    /// 送れたあとの知らせ (公開したか、直しの提案として預かったか)。
    @State private var sentMessage: String?
    @State private var showGuide = false
    @State private var showLineScanner = false

    private var text: String { drafts.draft(for: song.id).text }
    private var agreed: Bool { drafts.draft(for: song.id).agreed }
    private var textBinding: Binding<String> {
        Binding(get: { drafts.draft(for: song.id).text },
                set: { new in drafts.setText(song.id, new) })
    }
    private var agreedBinding: Binding<Bool> {
        Binding(get: { drafts.draft(for: song.id).agreed },
                set: { new in drafts.update(song.id) { $0.agreed = new } })
    }

    private var rubies: [RubyMark] { drafts.draft(for: song.id).rubies }
    /// 送る形の本文 (読み仮名を記法で入れたもの)。画面には出さない。
    private var markup: String { lyricRubyJoin(plain: text, marks: rubies) }

    private var check: LyricSubmissionCheck {
        lyricSubmissionCheck(text: markup, agreedToGuideline: agreed)
    }

    private var isDirty: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasFormCard {
                    ImasFormField(label: "曲", imprint: "SONG", systemImage: "music.note") {
                        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                            Text(song.title)
                            if let singer = song.singerLabel, !singer.isEmpty {
                                Text(singer).font(.imasFootnote).foregroundStyle(DS.ink2)
                            }
                        }
                    }
                }

                ImasFormCard {
                    ImasFormLink(label: "投稿ガイドライン", imprint: "GUIDE", systemImage: "book",
                                 value: "投稿できるもの・できないもの") { showGuide = true }
                }

                ImasFormCard {
                    if #available(iOS 18.0, *) {
                        LyricsRubyEditor(text: textBinding) { start, end, reading in
                            let songId = song.id
                            if let mark = lyricRubyMarkAt(plain: text, start: UInt32(start), end: UInt32(end), reading: reading) {
                                drafts.update(songId) { $0.rubies.append(mark) }
                            }
                        }
                    } else {
                        ImasFormTextArea(label: "歌詞", imprint: "LYRICS", systemImage: "text.quote",
                                         text: textBinding, prompt: "1 行ずつ改行して入力してください")
                    }
                }
                rubySection
                ocrButtons
                issueNotes

                ImasFormCard {
                    ImasFormToggle(label: "確認", imprint: "CHECK", title: "投稿ガイドラインを読み、それに沿って入力しました",
                                   isOn: agreedBinding)
                }

                Text("送った歌詞はすぐに公開され、運営があとから確認します。歌詞サイトから写した歌詞や、聴き取りの書き起こしは投稿できません。")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .navigationTitle("歌詞を投稿")
            .navigationDestination(isPresented: $showGuide) { LyricSubmissionGuideView() }
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.submit(
                canSubmit: check.canSubmit && !isSaving,
                isSubmitting: isSaving,
                onCancel: { isDirty ? (confirmDiscard = true) : dismiss() },
                onSubmit: { AppAnalytics.tap("lyric_submission.submit"); Task { await submit() } }
            ))
            .imasSavingOverlay(isSaving, label: "送信中")
            .fullScreenCover(isPresented: $showLineScanner) {
                LyricLineScannerView { scanned in
                    let songId = song.id
                    drafts.setText(songId, lyricOcrAppend(draft: drafts.draft(for: songId).text, recognized: scanned))
                }
            }
            .imasErrorAlert("送信できませんでした", message: $errorMessage)
            .imasDiscardConfirmation(isPresented: $confirmDiscard) { drafts.clear(song.id); dismiss() }
            .interactiveDismissDisabled(isDirty)
            .alert("歌詞を送りました", isPresented: Binding(get: { sentMessage != nil }, set: { if !$0 { sentMessage = nil } })) {
                Button("OK") { dismiss() }
            } message: {
                Text(sentMessage ?? "")
            }
        }
        .trackScreen("lyric_submission")
    }

    /// 歌詞カードの読み取り。映った歌詞を押した順に、塊の中は改行・塊の間は空行で入れる
    /// (行の区切りを歌詞カードどおりに取り込むため、これだけにする)。読んだ文字は本人が見直してから送る。
    @ViewBuilder
    private var ocrButtons: some View {
        if LyricLineScannerView.isAvailable {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Button {
                    AppAnalytics.tap("lyric_submission.line_scanner")
                    showLineScanner = true
                } label: {
                    Label("歌詞カードを読み取る", systemImage: "text.viewfinder")
                }
                .buttonStyle(.imas(.secondary, fillsWidth: true))
                ImasStepList(steps: lyricOcrSteps(tapScanner: true).map { .init(title: $0.title, detail: $0.detail) })
                    .padding(.top, DS.Space.gapTight)
                Text("文字の読み取りは端末の中だけで行い、映像はどこにも送りません。")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(isSaving)
        }
    }

    /// 付けた読み仮名の一覧 (外せる) と、送ったときの見た目の見本。記法は見せない。
    @ViewBuilder
    private var rubySection: some View {
        if !rubies.isEmpty {
            ImasFormCard {
                ImasFormField(label: "読み仮名", imprint: "RUBY", systemImage: "character.textbox") {
                    VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                        ForEach(Array(rubies.enumerated()), id: \.offset) { index, mark in
                            HStack(spacing: DS.Space.gap) {
                                Text("\(mark.base) → \(mark.reading)")
                                if !lyricRubyMarkFound(plain: text, mark: mark) {
                                    Text("歌詞に見つかりません")
                                        .font(.imasFootnote.weight(.semibold))
                                        .foregroundStyle(DS.danger)
                                }
                                Spacer(minLength: DS.Space.gap)
                                ImasIconButton(systemImage: "xmark", label: "\(mark.base) の読み仮名を外す", size: .small) {
                                    let songId = song.id
                                    drafts.update(songId) { d in
                                        if d.rubies.indices.contains(index) { d.rubies.remove(at: index) }
                                    }
                                }
                            }
                        }
                    }
                }
                ImasFormField(label: "見本", imprint: "PREVIEW", systemImage: "eye") {
                    ImasRubyPreview(text: markup)
                }
            }
        }
    }

    /// 行数・文字数と、コアが出した注意。送信を止める注意は朱で出す。
    private var issueNotes: some View {
        let check = check
        return VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            if check.lineCount > 0 {
                Text("\(check.lineCount) 行 · \(check.charCount) / \(lyricSubmissionMaxChars()) 字")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink3)
            }
            ForEach(Array(check.issues.enumerated()), id: \.offset) { _, issue in
                if issue != .empty {
                    Text(lyricSubmissionIssueMessage(issue: issue))
                        .font(.imasFootnote.weight(.semibold))
                        .foregroundStyle(lyricSubmissionIssueBlocks(issue: issue) ? DS.danger : DS.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .rubyLikeLines = issue {
                        Button("この行を消す") {
                            AppAnalytics.tap("lyric_submission.remove_ruby_lines")
                            drafts.update(song.id) {
                                $0.text = lyricRemoveLines(text: $0.text, indices: lyricRubyLikeLines(text: $0.text))
                            }
                        }
                        .buttonStyle(.imas(.secondary, size: .small))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() async {
        let check = check
        guard check.canSubmit else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let published = try await LyricSubmissionAPI.shared.submit(songId: song.id, text: check.normalized)
            drafts.clear(song.id)
            Logger.database.notice("lyric_submitted song=\(song.id, privacy: .public)")
            sentMessage = published
                ? "歌詞を公開しました。運営があとから確認します。ありがとうございました。"
                : "この曲には歌詞があるので、直しの提案として運営が確認します。ありがとうございました。"
        } catch {
            errorMessage = "時間をおいてもう一度お試しください。(\(error.localizedDescription))"
        }
    }
}

/// 歌詞の入力欄と「選んだ字に読み仮名を付ける」(iOS 18 から。文字の選択を読むため)。
/// 本文は書き換えず、選んだ範囲 (スカラーの位置) と読みを `onAdd` で返す。読み仮名は本文と分けて持つ。
@available(iOS 18.0, *)
private struct LyricsRubyEditor: View {
    @Binding var text: String
    let onAdd: (Int, Int, String) -> Void
    @State private var selection: TextSelection?
    @State private var pending: Range<Int>?
    @State private var reading = ""

    /// 選んでいる範囲 (Unicode スカラーの位置)。何も選んでいなければ nil。
    private var selectedScalars: Range<Int>? {
        guard case .selection(let range)? = selection?.indices, !range.isEmpty,
              range.upperBound <= text.endIndex else { return nil }
        let start = text.unicodeScalars.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.unicodeScalars.distance(from: text.startIndex, to: range.upperBound)
        return start..<end
    }

    var body: some View {
        ImasFormSelectableTextArea(label: "歌詞", imprint: "LYRICS", systemImage: "text.quote",
                                   text: $text, selection: $selection,
                                   prompt: "1 行ずつ改行して入力してください")
        ImasFormField(label: "読み仮名を付ける", imprint: "RUBY", systemImage: "character.textbox") {
            Button {
                AppAnalytics.tap("lyric_submission.add_ruby")
                pending = selectedScalars
                reading = ""
            } label: {
                Label(selectedScalars == nil ? "歌詞の字を選んでください" : "選んだ字に読み仮名を付ける", systemImage: "plus")
            }
            .buttonStyle(.imas(.secondary, size: .small))
            .disabled(selectedScalars == nil)
        }
        .alert("読み仮名", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            TextField("歌詞カードに振られている読み", text: $reading)
            Button("付ける") {
                if let range = pending { onAdd(range.lowerBound, range.upperBound, reading) }
                pending = nil
                selection = nil
            }
            Button("キャンセル", role: .cancel) { pending = nil }
        } message: {
            Text("歌詞カードに振られている読み仮名だけを付けてください。")
        }
    }
}
