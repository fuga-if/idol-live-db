import os
import PhotosUI
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
    @State private var showCamera = false
    @State private var photoPicks: [PhotosPickerItem] = []
    @State private var isReading = false
    @State private var ocrMessage: String?
    @State private var showGuide = false
    @State private var liveText = LiveTextCapture()

    private var text: String { drafts.draft(for: song.id).text }
    private var agreed: Bool { drafts.draft(for: song.id).agreed }
    private var textBinding: Binding<String> {
        Binding(get: { drafts.draft(for: song.id).text },
                set: { new in drafts.update(song.id) { $0.text = new } })
    }
    private var agreedBinding: Binding<Bool> {
        Binding(get: { drafts.draft(for: song.id).agreed },
                set: { new in drafts.update(song.id) { $0.agreed = new } })
    }

    private var check: LyricSubmissionCheck {
        lyricSubmissionCheck(text: text, agreedToGuideline: agreed)
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
                    ImasFormTextArea(label: "歌詞", imprint: "LYRICS", systemImage: "text.quote",
                                     text: textBinding, prompt: "1 行ずつ改行して入力してください")
                }
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
            .imasSavingOverlay(isSaving || isReading, label: isReading ? "読み取り中" : "送信中")
            .fullScreenCover(isPresented: $showCamera) {
                PaperCardCamera(maxPages: 10, onFinish: { images in
                    showCamera = false
                    Task { await read(images) }
                }, onCancel: { showCamera = false })
                .ignoresSafeArea()
            }
            .onChange(of: photoPicks) { _, picks in
                guard !picks.isEmpty else { return }
                Task {
                    var images: [UIImage] = []
                    for pick in picks {
                        if let data = try? await pick.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    photoPicks = []
                    await read(images)
                }
            }
            .imasErrorAlert("送信できませんでした", message: $errorMessage)
            .imasErrorAlert("文字を読み取れませんでした", message: $ocrMessage)
            .imasDiscardConfirmation(isPresented: $confirmDiscard) { drafts.clear(song.id); dismiss() }
            .interactiveDismissDisabled(isDirty)
            .alert("歌詞を送りました", isPresented: Binding(get: { sentMessage != nil }, set: { if !$0 { sentMessage = nil } })) {
                Button("OK") { dismiss() }
            } message: {
                Text(sentMessage ?? "")
            }
        }
        .onDisappear { liveText.stop() }
        .trackScreen("lyric_submission")
    }

    /// 歌詞カードを撮る・写真から読む。読んだ文字は入力欄に足すだけで、本人が見直してから送る。
    private var ocrButtons: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            HStack(spacing: DS.Space.gap) {
                if liveText.isAvailable {
                    // メモアプリと同じ「テキストをスキャン」。塊ごとに選んで入れられ、書類スキャンより読みがよい。
                    Button {
                        AppAnalytics.tap("lyric_submission.live_text")
                        let songId = song.id
                        liveText.start { captured in
                            drafts.update(songId) { $0.text = lyricOcrAppend(draft: $0.text, recognized: captured) }
                        }
                    } label: {
                        Label("テキストをスキャン", systemImage: "text.viewfinder")
                    }
                    .buttonStyle(.imas(.secondary, fillsWidth: true))
                    .background { LiveTextCaptureAnchor(capture: liveText).frame(width: 0, height: 0) }
                } else if PaperCardCamera.isAvailable {
                    Button {
                        AppAnalytics.tap("lyric_submission.ocr_camera")
                        showCamera = true
                    } label: {
                        Label("歌詞カードを撮る", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(.imas(.secondary, fillsWidth: true))
                }
                PhotosPicker(selection: $photoPicks, maxSelectionCount: 10, matching: .images) {
                    Label("写真から読む", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.imas(.secondary, fillsWidth: true))
            }
            ImasStepList(steps: lyricOcrSteps(liveText: liveText.isAvailable).map { .init(title: $0.title, detail: $0.detail) })
                .padding(.top, DS.Space.gapTight)
            Text("文字の読み取りは端末の中だけで行い、写真はどこにも送りません。")
                .font(.imasFootnote)
                .foregroundStyle(DS.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(isReading || isSaving)
    }

    private func read(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        isReading = true
        defer { isReading = false }
        let reading = await LyricsCardOCR.read(images)
        let recognized = reading.text
        if recognized.isEmpty {
            ocrMessage = "明るい所で、歌詞カードが画面いっぱいに写るように撮ってください。"
        } else {
            let songId = song.id
            drafts.update(songId) {
                $0.text = lyricOcrAppend(draft: $0.text, recognized: recognized)
                $0.doubtfulLines += reading.doubtfulLines
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
            let doubtful = drafts.draft(for: song.id).doubtfulLines
            if !doubtful.isEmpty {
                Text("読み取りに自信の無い行があります。歌詞カードと見比べてください:\n" + doubtful.prefix(12).map { "・\($0)" }.joined(separator: "\n"))
                    .font(.imasFootnote.weight(.semibold))
                    .foregroundStyle(DS.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
