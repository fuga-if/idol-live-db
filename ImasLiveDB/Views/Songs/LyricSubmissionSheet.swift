import os
import PhotosUI
import SwiftUI

/// 歌詞を投稿するシート。CD の歌詞カードなどの一次ソースを見て入力した歌詞を送る。
///
/// 送った歌詞は確認待ちで預かられ、公開はモデレーターの確認後 (`LyricSubmissionAPI`)。
/// 投稿ガイドラインに同意しないと送れない。入力元は書かせない (規約で縛る)。
/// 本文の整え方・上限・注意はコア (`lyricSubmissionCheck`) が決める。
struct LyricSubmissionSheet: View {
    let song: Song

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var agreed = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @State private var sent = false
    @State private var showCamera = false
    @State private var photoPicks: [PhotosPickerItem] = []
    @State private var isReading = false
    @State private var ocrMessage: String?
    @State private var showGuide = false

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
                                     text: $text, prompt: "1 行ずつ改行して入力してください")
                }
                ocrButtons
                issueNotes

                ImasFormCard {
                    ImasFormToggle(label: "確認", imprint: "CHECK", title: "投稿ガイドラインを読み、それに沿って入力しました",
                                   isOn: $agreed)
                }

                Text("送った歌詞は運営が確認してから公開します。歌詞サイトから写した歌詞や、聴き取りの書き起こしは投稿できません。")
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
            .imasDiscardConfirmation(isPresented: $confirmDiscard) { dismiss() }
            .interactiveDismissDisabled(isDirty)
            .alert("歌詞を送りました", isPresented: $sent) {
                Button("OK") { dismiss() }
            } message: {
                Text("運営が確認してから公開します。ありがとうございました。")
            }
        }
        .trackScreen("lyric_submission")
    }

    /// 歌詞カードを撮る・写真から読む。読んだ文字は入力欄に足すだけで、本人が見直してから送る。
    private var ocrButtons: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            HStack(spacing: DS.Space.gap) {
                if PaperCardCamera.isAvailable {
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
            Text("文字の読み取りは端末の中だけで行い、写真は送りません。読み取った歌詞は誤りがないか見直してから送ってください。")
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
        let recognized = await LyricsCardOCR.read(images)
        if recognized.isEmpty {
            ocrMessage = "明るい所で、歌詞カードが画面いっぱいに写るように撮ってください。"
        } else {
            text = lyricOcrAppend(draft: text, recognized: recognized)
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
            try await LyricSubmissionAPI.shared.submit(songId: song.id, text: check.normalized)
            Logger.database.notice("lyric_submitted song=\(song.id, privacy: .public)")
            sent = true
        } catch {
            errorMessage = "時間をおいてもう一度お試しください。(\(error.localizedDescription))"
        }
    }
}
