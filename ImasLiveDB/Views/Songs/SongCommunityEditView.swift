import os
import SwiftUI

// MARK: - Sheet 駆動ターゲット (新規 / 既存編集)

/// コーレス / 参考動画の投稿・編集シートを `.sheet(item:)` で駆動するための識別子。
/// `.create` は新規投稿、`.edit(model)` は既存編集。`Identifiable` 準拠で sheet を出す。
enum SongCommunityEditTarget<Model: Identifiable>: Identifiable where Model.ID == String {
    case create
    case edit(Model)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let m): return "edit_\(m.id)"
        }
    }

    var editing: Model? {
        if case .edit(let m) = self { return m }
        return nil
    }
}

// MARK: - SongCall (コーレス) 編集 / 投稿フォーム
//
// 確定契約 §4: コーレス (SongCall) / 参考動画 (SongVideo) をオープン編集に復活する。
// 旧 CallResponseFormView / YouTubeReferenceFormView は削除済みなので、EditService 経由の
// 軽量フォームを新設する。ログイン済み全ユーザーが投稿/編集できる (DetailSheet から導線)。
//
// サーバ (master_validators.ts FIELD_RULES) と厳密一致させるフィールド (CKRecordMapper 既存名):
//   SongCall  : songId(required), callText(required, max5000), sourceUrl(http URL, 任意)
//   SongVideo : songId(required), youtubeUrl(required, YouTube URL), videoTitle(任意 max300),
//               note(任意 max1000)
// recordName 採番はサーバ (create で省略 → call_<uuid> / ytref_<uuid>)。createdAt はサーバ権威。

/// コーレス投稿 / 編集フォーム。
struct CallEditView: View {
    let songId: String
    let mode: EditMode<SongCall>
    /// 保存成功後にローカル反映を呼び出し側へ通知する (DetailSheet がセクション再読込)。
    var onSaved: () -> Void = {}

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var callText: String
    @State private var sourceUrl: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// 下書き保持: 歌詞確認などでアプリがバックグラウンド/終了されても入力を失わないよう、
    /// 新規投稿の入力内容を SceneStorage に退避する (復元時に songId 一致で照合)。
    @SceneStorage("draft.songCall.create") private var draftStore: String = ""

    private static let maxCallText = 5000

    /// 新規投稿用。
    init(songId: String, onSaved: @escaping () -> Void = {}) {
        self.songId = songId
        self.mode = .create
        self.onSaved = onSaved
        _callText = State(initialValue: "")
        _sourceUrl = State(initialValue: "")
    }

    /// 既存編集用。
    init(call: SongCall, onSaved: @escaping () -> Void = {}) {
        self.songId = call.songId
        self.mode = .update(original: call)
        self.onSaved = onSaved
        _callText = State(initialValue: call.callText)
        _sourceUrl = State(initialValue: call.sourceUrl ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("コーレス・コール本文", text: $callText, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Text("コール本文")
                } footer: {
                    Text("コールやMIX、ペンライトの振り方など。\(callText.count)/\(Self.maxCallText) 文字")
                        .foregroundStyle(callText.count > Self.maxCallText ? DS.danger : DS.ink2)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section {
                    TextField("出典 URL (任意)", text: $sourceUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("出典")
                } footer: {
                    Text("コール表などの参考ページがあれば。http(s) のみ。")
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle(mode.isCreate ? "コーレスを投稿" : "コーレスを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { clearDraft(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { AppAnalytics.tap("call_edit.save"); Task { await save() } }
                        .disabled(isSaving || !isValid)
                }
            }
            .overlay { if isSaving { SavingOverlay() } }
            .alert("エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: { Text(errorMessage ?? "") }
            .trackScreen("call_edit")
        }
        .onAppear { restoreDraft() }
        .onChange(of: callText) { persistDraft() }
        .onChange(of: sourceUrl) { persistDraft() }
    }

    // MARK: - Draft 退避 (新規投稿のみ)

    private struct Draft: Codable { var songId: String; var callText: String; var sourceUrl: String }

    private func persistDraft() {
        guard mode.isCreate else { return }
        let draft = Draft(songId: songId, callText: callText, sourceUrl: sourceUrl)
        if let data = try? JSONEncoder().encode(draft) {
            draftStore = String(decoding: data, as: UTF8.self)
        }
    }

    private func restoreDraft() {
        guard mode.isCreate, !draftStore.isEmpty,
              let data = draftStore.data(using: .utf8),
              let draft = try? JSONDecoder().decode(Draft.self, from: data),
              draft.songId == songId else { return }
        if callText.isEmpty { callText = draft.callText }
        if sourceUrl.isEmpty { sourceUrl = draft.sourceUrl }
    }

    private func clearDraft() { draftStore = "" }

    private var trimmedCallText: String { callText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSourceUrl: String { sourceUrl.trimmingCharacters(in: .whitespaces) }

    private var isValid: Bool {
        !trimmedCallText.isEmpty && trimmedCallText.count <= Self.maxCallText
    }

    private func save() async {
        guard isValid else {
            errorMessage = "コール本文を入力してください (最大 \(Self.maxCallText) 文字)"
            return
        }
        // 出典 URL を入力したなら http(s) 妥当性をチェック (サーバ validator と一致)。
        if !trimmedSourceUrl.isEmpty, URL.safeHTTP(string: trimmedSourceUrl) == nil {
            errorMessage = "出典 URL は http(s):// で始まる正しい URL を入力してください"
            return
        }

        isSaving = true
        defer { isSaving = false }

        var fields: [String: AnyEncodable] = [
            "songId": AnyEncodable(songId),
            "callText": AnyEncodable(trimmedCallText),
        ]
        // update はサーバ側マージ (未送信 = 現状維持)。空にした場合は null 明示送信でクリア。
        fields["sourceUrl"] = AnyEncodable.clearable(trimmedSourceUrl, original: mode.original?.sourceUrl)

        // create は recordName を省略しサーバ採番 (call_<uuid>)。edit は既存 id を送る。
        let op = EditService.EditOperation(
            op: mode.isCreate ? .create : .update,
            recordType: "SongCall",
            recordName: mode.original?.id,
            fields: fields
        )

        do {
            let resp = try await EditService.shared.submit(
                ops: [op],
                summary: mode.isCreate ? "コーレスを追加" : "コーレスを編集"
            )
            let resolvedId = resp.primaryRecordName(fallback: mode.original?.id)
                ?? "call_\(UUID().uuidString.lowercased())"
            let saved = SongCall(
                id: resolvedId,
                songId: songId,
                callText: trimmedCallText,
                sourceUrl: trimmedSourceUrl.isEmpty ? nil : trimmedSourceUrl,
                createdAt: mode.original?.createdAt ?? ISO8601DateFormatter.shared.string(from: Date()),
                authorDisplayName: mode.original?.authorDisplayName ?? AuthService.shared.userName
            )
            try await AppContainer.shared.songWriting.upsertSongCalls([saved])
            Logger.database.notice("song_call_\(mode.isCreate ? "created" : "edited", privacy: .public)")
            clearDraft()
            onSaved()
            dismiss()
        } catch {
            errorMessage = friendlyEditError(error)
        }
    }
}

// MARK: - SongVideo (参考動画) 編集 / 投稿フォーム

/// 参考動画 (YouTube) 投稿 / 編集フォーム。
struct VideoEditView: View {
    let songId: String
    let mode: EditMode<SongVideo>
    var onSaved: () -> Void = {}

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var youtubeUrl: String
    @State private var videoTitle: String
    @State private var note: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// 下書き保持: バックグラウンド/終了されても新規投稿の入力を失わない (songId 照合で復元)。
    @SceneStorage("draft.songVideo.create") private var draftStore: String = ""

    private static let maxTitle = 300
    private static let maxNote = 1000

    init(songId: String, onSaved: @escaping () -> Void = {}) {
        self.songId = songId
        self.mode = .create
        self.onSaved = onSaved
        _youtubeUrl = State(initialValue: "")
        _videoTitle = State(initialValue: "")
        _note = State(initialValue: "")
    }

    init(video: SongVideo, onSaved: @escaping () -> Void = {}) {
        self.songId = video.songId
        self.mode = .update(original: video)
        self.onSaved = onSaved
        _youtubeUrl = State(initialValue: video.youtubeUrl)
        _videoTitle = State(initialValue: video.videoTitle ?? "")
        _note = State(initialValue: video.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("YouTube URL", text: $youtubeUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("動画 URL")
                } footer: {
                    Text("YouTube の watch / youtu.be / shorts / embed URL に対応。")
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section {
                    TextField("動画タイトル (任意)", text: $videoTitle)
                    TextField("メモ (任意)", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("補足")
                } footer: {
                    Text("どの公演の映像かなどの補足。メモ \(note.count)/\(Self.maxNote) 文字")
                        .foregroundStyle(note.count > Self.maxNote ? DS.danger : DS.ink2)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle(mode.isCreate ? "参考動画を投稿" : "参考動画を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { clearDraft(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { AppAnalytics.tap("video_edit.save"); Task { await save() } }
                        .disabled(isSaving || !isValid)
                }
            }
            .overlay { if isSaving { SavingOverlay() } }
            .alert("エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: { Text(errorMessage ?? "") }
            .trackScreen("video_edit")
        }
        .onAppear { restoreDraft() }
        .onChange(of: youtubeUrl) { persistDraft() }
        .onChange(of: videoTitle) { persistDraft() }
        .onChange(of: note) { persistDraft() }
    }

    // MARK: - Draft 退避 (新規投稿のみ)

    private struct Draft: Codable {
        var songId: String; var youtubeUrl: String; var videoTitle: String; var note: String
    }

    private func persistDraft() {
        guard mode.isCreate else { return }
        let draft = Draft(songId: songId, youtubeUrl: youtubeUrl, videoTitle: videoTitle, note: note)
        if let data = try? JSONEncoder().encode(draft) {
            draftStore = String(decoding: data, as: UTF8.self)
        }
    }

    private func restoreDraft() {
        guard mode.isCreate, !draftStore.isEmpty,
              let data = draftStore.data(using: .utf8),
              let draft = try? JSONDecoder().decode(Draft.self, from: data),
              draft.songId == songId else { return }
        if youtubeUrl.isEmpty { youtubeUrl = draft.youtubeUrl }
        if videoTitle.isEmpty { videoTitle = draft.videoTitle }
        if note.isEmpty { note = draft.note }
    }

    private func clearDraft() { draftStore = "" }

    private var trimmedUrl: String { youtubeUrl.trimmingCharacters(in: .whitespaces) }
    private var trimmedTitle: String { videoTitle.trimmingCharacters(in: .whitespaces) }
    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        Self.isYouTubeURL(trimmedUrl)
            && trimmedTitle.count <= Self.maxTitle
            && trimmedNote.count <= Self.maxNote
    }

    /// YouTube URL 簡易判定 (サーバ validator の YouTube 正規表現に合わせたクライアント先行チェック)。
    /// watch?v= / youtu.be/ / shorts/ / embed/ を許容する。
    static func isYouTubeURL(_ s: String) -> Bool {
        guard let url = URL.safeHTTP(string: s), let host = url.host?.lowercased() else { return false }
        let isYouTubeHost = host == "youtu.be"
            || host == "youtube.com" || host == "www.youtube.com"
            || host == "m.youtube.com" || host == "music.youtube.com"
        return isYouTubeHost
    }

    private func save() async {
        guard Self.isYouTubeURL(trimmedUrl) else {
            errorMessage = "YouTube の URL を入力してください"
            return
        }
        guard trimmedTitle.count <= Self.maxTitle else {
            errorMessage = "タイトルは \(Self.maxTitle) 文字以内で入力してください"
            return
        }
        guard trimmedNote.count <= Self.maxNote else {
            errorMessage = "メモは \(Self.maxNote) 文字以内で入力してください"
            return
        }

        isSaving = true
        defer { isSaving = false }

        var fields: [String: AnyEncodable] = [
            "songId": AnyEncodable(songId),
            "youtubeUrl": AnyEncodable(trimmedUrl),
        ]
        // update はサーバ側マージ (未送信 = 現状維持)。空にした場合は null 明示送信でクリア。
        fields["videoTitle"] = AnyEncodable.clearable(trimmedTitle, original: mode.original?.videoTitle)
        fields["note"] = AnyEncodable.clearable(trimmedNote, original: mode.original?.note)

        let op = EditService.EditOperation(
            op: mode.isCreate ? .create : .update,
            recordType: "SongVideo",
            recordName: mode.original?.id,
            fields: fields
        )

        do {
            let resp = try await EditService.shared.submit(
                ops: [op],
                summary: mode.isCreate ? "参考動画を追加" : "参考動画を編集"
            )
            let resolvedId = resp.primaryRecordName(fallback: mode.original?.id)
                ?? "ytref_\(UUID().uuidString.lowercased())"
            let saved = SongVideo(
                id: resolvedId,
                songId: songId,
                youtubeUrl: trimmedUrl,
                videoTitle: trimmedTitle.isEmpty ? nil : trimmedTitle,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                createdAt: mode.original?.createdAt ?? ISO8601DateFormatter.shared.string(from: Date()),
                authorDisplayName: mode.original?.authorDisplayName ?? AuthService.shared.userName
            )
            try await AppContainer.shared.songWriting.upsertSongVideos([saved])
            Logger.database.notice("song_video_\(mode.isCreate ? "created" : "edited", privacy: .public)")
            clearDraft()
            onSaved()
            dismiss()
        } catch {
            errorMessage = friendlyEditError(error)
        }
    }
}

// MARK: - Shared helpers

/// 保存中のフルスクリーンオーバーレイ (SongEditView 等と同じ見た目)。
private struct SavingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView("保存中…").padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// EditService.submit の throw を日本語の短文へ変換する。
private func friendlyEditError(_ error: Error) -> String {
    switch error {
    case APIClientError.notAuthorized:
        return "認証の有効期限が切れています。再度サインインしてください。"
    case APIClientError.rateLimited:
        return "投稿が多すぎます。しばらく待ってからお試しください。"
    default:
        return "保存に失敗しました: \(error.localizedDescription)"
    }
}
