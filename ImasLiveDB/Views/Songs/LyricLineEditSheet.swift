import os
import PhotosUI
import SwiftUI

/// 公開中の歌詞の 1 行だけを直すシート (`PUT /songs/{id}/lyric-lines/{line_id}`)。
///
/// 誤字の直しのたびに全文を打ち直させないための入口。行の数は変わらないので、行に付いた
/// タイミング・歌割・コールはその行に残る。送るとすぐ公開され、前の版が残る (投稿と同じ扱い)。
/// 読み仮名は記法を見せず、本文と分けて持つ (`lyricRubySplit` / `lyricRubyRebase` / `lyricRubyJoin`)。
/// 歌詞カードをカメラや写真から読み、読んだ行を選んで入れられる (端末の中だけで読む)。
struct LyricLineEditSheet: View {
    let songId: String
    let line: LyricLine
    /// 直したあとに歌詞を取り直す。
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// 一度同意した人には同意を求め直さない (同意の中身は投稿と同じガイドライン)。
    @AppStorage("lyricLineEdit.agreedToGuideline") private var agreed = false
    @State private var plain: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showGuide = false
    @State private var showLineScanner = false
    @State private var photoPicks: [PhotosPickerItem] = []
    @State private var isReading = false
    @State private var ocrMessage: String?
    /// 読み取った行 (2 行以上読めたとき、どれを入れるか選んでもらう)。
    @State private var scannedLines: [String] = []
    private let original: RubySplit

    init(songId: String, line: LyricLine, onSaved: @escaping () -> Void) {
        self.songId = songId
        self.line = line
        self.onSaved = onSaved
        let split = lyricRubySplit(text: line.text)
        original = split
        _plain = State(initialValue: split.plain)
    }

    /// 送る形 (読み仮名を、直した本文に付け直して記法で入れたもの)。
    private var markup: String {
        lyricRubyJoin(plain: plain, marks: lyricRubyRebase(oldPlain: original.plain, newPlain: plain, marks: original.marks))
    }

    private var check: LyricSubmissionCheck { lyricSubmissionCheck(text: markup, agreedToGuideline: agreed) }
    private var isChanged: Bool { check.normalized != line.text }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasFormCard {
                    ImasFormTextField(label: "この行", imprint: "LINE", systemImage: "text.quote", text: $plain)
                    if !original.marks.isEmpty {
                        ImasFormField(label: "見本", imprint: "PREVIEW", systemImage: "eye") {
                            ImasRubyPreview(text: markup)
                        }
                    }
                }
                issueNotes
                ocrSection

                ImasFormCard {
                    ImasFormLink(label: "投稿ガイドライン", imprint: "GUIDE", systemImage: "book",
                                 value: "投稿できるもの・できないもの") { showGuide = true }
                    ImasFormToggle(label: "確認", imprint: "CHECK", title: "投稿ガイドラインを読み、それに沿って入力しました",
                                   isOn: $agreed)
                }

                Text("直した行はすぐに公開され、運営があとから確認します。この行のタイミング・パート分け・コールはそのまま残ります。")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .navigationTitle("この行を直す")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showGuide) { LyricSubmissionGuideView() }
            .imasSheetToolbar(.submit(
                canSubmit: check.canSubmit && isChanged && !isSaving,
                isSubmitting: isSaving,
                onCancel: { dismiss() },
                onSubmit: { AppAnalytics.tap("lyric_line_edit.submit"); Task { await submit() } }
            ))
            .imasSavingOverlay(isSaving || isReading, label: isReading ? "読み取り中" : "送信中")
            .fullScreenCover(isPresented: $showLineScanner) {
                LyricLineScannerView { scanned in take(scanned) }
            }
            .onChange(of: photoPicks) { _, picks in
                guard !picks.isEmpty else { return }
                Task {
                    let images = await LyricsCardOCR.images(from: picks)
                    photoPicks = []
                    guard !images.isEmpty else { return }
                    isReading = true
                    let text = await LyricsCardOCR.read(images).text
                    isReading = false
                    if text.isEmpty {
                        ocrMessage = "歌詞カードが画面いっぱいに写った、明るい写真を選んでください。"
                    } else {
                        take(text)
                    }
                }
            }
            .imasErrorAlert("文字を読み取れませんでした", message: $ocrMessage)
            .imasErrorAlert("送信できませんでした", message: $errorMessage)
            .interactiveDismissDisabled(isChanged)
        }
        .trackScreen("lyric_line_edit")
    }

    /// 歌詞カードの読み取り。読んだ行が 1 つならそのまま入れ、2 つ以上なら押して選んでもらう。
    private var ocrSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            if LyricLineScannerView.isAvailable {
                Button {
                    AppAnalytics.tap("lyric_line_edit.line_scanner")
                    showLineScanner = true
                } label: {
                    Label("歌詞カードを読み取る", systemImage: "text.viewfinder")
                }
                .buttonStyle(.imas(.secondary, fillsWidth: true))
            }
            PhotosPicker(selection: $photoPicks, maxSelectionCount: 1, matching: .images) {
                Label("写真から読む", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.imas(.secondary, fillsWidth: true))
            if !scannedLines.isEmpty {
                ImasFormCard {
                    ImasFormField(label: "読み取った行", imprint: "SCAN", systemImage: "text.viewfinder") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(scannedLines.enumerated()), id: \.offset) { _, candidate in
                                Button {
                                    plain = candidate
                                    scannedLines = []
                                } label: {
                                    Text(candidate)
                                        .frame(maxWidth: .infinity, minHeight: DS.Size.touch, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Text("文字の読み取りは端末の中だけで行い、映像や写真はどこにも送りません。")
                .font(.imasFootnote)
                .foregroundStyle(DS.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(isSaving || isReading)
    }

    /// 読み取った文字を入れる。行が 1 つならそのまま、2 つ以上なら選ぶ候補にする。
    private func take(_ recognized: String) {
        let lines = recognized.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count == 1 {
            plain = lines[0]
            scannedLines = []
        } else {
            scannedLines = lines
        }
    }

    /// コアが出した注意。送信を止める注意は朱で出す (空は送るボタンで分かるので出さない)。
    private var issueNotes: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            ForEach(Array(check.issues.enumerated()), id: \.offset) { _, issue in
                if issue != .empty {
                    Text(lyricSubmissionIssueMessage(issue: issue))
                        .font(.imasFootnote.weight(.semibold))
                        .foregroundStyle(lyricSubmissionIssueBlocks(issue: issue) ? DS.danger : DS.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() async {
        let check = check
        guard check.canSubmit, isChanged else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await LyricSubmissionAPI.shared.editLine(songId: songId, lineId: line.id, text: check.normalized)
            Logger.database.notice("lyric_line_edited song=\(songId, privacy: .public)")
            onSaved()
            dismiss()
        } catch {
            errorMessage = "時間をおいてもう一度お試しください。(\(error.localizedDescription))"
        }
    }
}
