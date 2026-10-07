import os
import SwiftUI

/// Song 編集 / 新規作成。ログイン済みユーザーが利用可能。
/// Apple Music ID / アートワーク URL / プレビュー URL をすぐ直せる (ジャケ写差替えや誤紐付け修正)。
///
/// 新規作成時 (`.create`):
/// - 歌唱アイドルを 1 名以上選択し、SongArtist(role="original") を同一 batch で作成する
///   (一覧アイコンの根拠データ。MEMORY: feedback_song_artists_original_required)。
/// - Song の recordName はクライアント生成 (`song_<uuid>`) し、SongArtist が参照できるようにする
///   (サーバ採番だと batch 内で song の ID を参照できないため)。
struct SongEditView: View {
    let mode: EditMode<Song>

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var titleKana: String
    @State private var brandId: String
    @State private var songType: String
    @State private var appleMusicId: String
    @State private var appleMusicAlbumId: String
    @State private var artworkUrl: String
    @State private var previewUrl: String
    @State private var cdSeries: String
    @State private var cdTitle: String
    @State private var lyricsUrl: String
    @State private var unitName: String
    @State private var lyricist: String
    @State private var composer: String
    @State private var arranger: String
    @State private var releaseDate: String
    @State private var streamingDate: String
    @State private var cdReleaseDate: String
    @State private var singerLabel: String
    @State private var note: String
    @State private var isrc: String
    @State private var durationSecText: String
    @State private var allBrands: [Brand] = []

    // 新規作成時の歌唱アイドル選択 (SongArtist role=original)。
    @State private var allIdols: [Idol] = []
    @State private var idolById: [String: Idol] = [:]
    @State private var artistIdolIds: Set<String> = []
    @State private var showArtistPicker = false

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var requestSent = false

    /// 選べる曲種別 (値と語はコアの vocabulary。マスタにある 5 種)。
    private let songTypes = Vocab.table.songTypes

    /// 既存編集用。
    init(song: Song) {
        self.mode = .update(original: song)
        _title = State(initialValue: song.title)
        _titleKana = State(initialValue: song.titleKana ?? "")
        _brandId = State(initialValue: song.brandId ?? "")
        _songType = State(initialValue: song.songType)
        _appleMusicId = State(initialValue: song.appleMusicId ?? "")
        _appleMusicAlbumId = State(initialValue: song.appleMusicAlbumId ?? "")
        _artworkUrl = State(initialValue: song.artworkUrl ?? "")
        _previewUrl = State(initialValue: song.previewUrl ?? "")
        _cdSeries = State(initialValue: song.cdSeries ?? "")
        _cdTitle = State(initialValue: song.cdTitle ?? "")
        _lyricsUrl = State(initialValue: song.lyricsUrl ?? "")
        _unitName = State(initialValue: song.unitName ?? "")
        _lyricist = State(initialValue: song.lyricist ?? "")
        _composer = State(initialValue: song.composer ?? "")
        _arranger = State(initialValue: song.arranger ?? "")
        _releaseDate = State(initialValue: song.releaseDate ?? "")
        _streamingDate = State(initialValue: song.streamingDate ?? "")
        _cdReleaseDate = State(initialValue: song.cdReleaseDate ?? "")
        _singerLabel = State(initialValue: song.singerLabel ?? "")
        _note = State(initialValue: song.note ?? "")
        _isrc = State(initialValue: song.isrc ?? "")
        _durationSecText = State(initialValue: song.durationSec.map(String.init) ?? "")
    }

    /// 新規作成用。ブランドの初期選択だけ受け取る。
    init(newSongBrandId: String? = nil) {
        self.mode = .create
        _title = State(initialValue: "")
        _titleKana = State(initialValue: "")
        _brandId = State(initialValue: newSongBrandId ?? "")
        _songType = State(initialValue: "solo")
        _appleMusicId = State(initialValue: "")
        _appleMusicAlbumId = State(initialValue: "")
        _artworkUrl = State(initialValue: "")
        _previewUrl = State(initialValue: "")
        _cdSeries = State(initialValue: "")
        _cdTitle = State(initialValue: "")
        _lyricsUrl = State(initialValue: "")
        _unitName = State(initialValue: "")
        _lyricist = State(initialValue: "")
        _composer = State(initialValue: "")
        _arranger = State(initialValue: "")
        _releaseDate = State(initialValue: "")
        _streamingDate = State(initialValue: "")
        _cdReleaseDate = State(initialValue: "")
        _singerLabel = State(initialValue: "")
        _note = State(initialValue: "")
        _isrc = State(initialValue: "")
        _durationSecText = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                ImasListSection("基本情報") {
                    if let original = mode.original {
                        ImasValueRow(key: "ID", value: original.id, expandable: true)
                    }
                    ImasTextFieldRow(title: "タイトル", text: $title)
                    ImasTextFieldRow(title: "タイトル (カナ)", text: $titleKana)
                    ImasMenuRow(title: "ブランド", options: [""] + allBrands.map(\.id), selection: $brandId) { id in
                        id.isEmpty ? "未指定" : (allBrands.first { $0.id == id }?.name ?? id)
                    }
                    ImasMenuRow(title: "種別", options: songTypes.map(\.value), selection: $songType) { value in
                        songTypes.first { $0.value == value }?.shortLabel ?? value
                    }
                    ImasTextFieldRow(title: "ユニット名", text: $unitName)
                }

                if mode.isCreate {
                    artistSection
                }

                ImasListSection("制作情報") {
                    ImasTextFieldRow(title: "作詞", text: $lyricist)
                    ImasTextFieldRow(title: "作曲", text: $composer)
                    ImasTextFieldRow(title: "編曲", text: $arranger)
                    ImasTextFieldRow(title: "初出", text: $releaseDate, prompt: "YYYY-MM-DD",
                                     keyboard: .numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ImasTextFieldRow(title: "CD 発売日", text: $cdReleaseDate, prompt: "YYYY-MM-DD",
                                     keyboard: .numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ImasTextFieldRow(title: "配信開始日", text: $streamingDate, prompt: "YYYY-MM-DD",
                                     keyboard: .numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ImasTextFieldRow(title: "歌唱表記", text: $singerLabel, prompt: "例: 春香・千早")
                    ImasTextFieldRow(title: "補足", text: $note, prompt: "例: ミリシタ 1 周年記念楽曲")
                    ImasTextFieldRow(title: "再生時間 (秒)", text: $durationSecText, keyboard: .numberPad)
                }

                ImasListSection("Apple Music") {
                    ImasTextFieldRow(title: "apple_music_id", text: $appleMusicId, keyboard: .numberPad)
                    ImasTextFieldRow(title: "apple_music_album_id", text: $appleMusicAlbumId, keyboard: .numberPad)
                    ImasTextFieldRow(title: "artwork URL", text: $artworkUrl, keyboard: .URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ImasTextFieldRow(title: "preview URL", text: $previewUrl, keyboard: .URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                ImasListSection("CD / その他") {
                    ImasTextFieldRow(title: "cd_series", text: $cdSeries)
                    ImasTextFieldRow(title: "cd_title", text: $cdTitle)
                    ImasTextFieldRow(title: "ISRC", text: $isrc)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ImasTextFieldRow(title: "歌詞 URL", text: $lyricsUrl, keyboard: .URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if !mode.isCreate {
                    ImasListSection(footer: "誤紐付けで他の曲が再生されるときに使う。サブスク未配信の曲はクリアすべき。") {
                        ImasActionRow(title: "Apple Music 関連を全て空にする", kind: .destructive) {
                            appleMusicId = ""
                            appleMusicAlbumId = ""
                            artworkUrl = ""
                            previewUrl = ""
                        }
                    }
                }
            }
            .imasForm()
            .navigationTitle(mode.isCreate ? "曲を追加" : "曲編集")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(
                canSave: !isSaving && !title.trimmingCharacters(in: .whitespaces).isEmpty,
                onCancel: { dismiss() },
                onSave: { AppAnalytics.tap("song_edit.save"); Task { await save() } }
            ))
            .imasSavingOverlay(isSaving, label: "保存中")
            .imasErrorAlert("エラー", message: $errorMessage)
            .editRequestSentAlert(isPresented: $requestSent, onDismiss: { dismiss() })
            .sheet(isPresented: $showArtistPicker) {
                IdolPickerView(title: "歌唱アイドル", idols: allIdols, selected: artistIdolIds) { newSelection in
                    artistIdolIds = newSelection
                    showArtistPicker = false
                }
                .environment(database)
            }
            .task {
                allBrands = (try? await AppContainer.shared.brandReading.brands()) ?? []
                if mode.isCreate {
                    allIdols = (try? await AppContainer.shared.idolReading.allIdolsForPicker()) ?? []
                    idolById = Dictionary(uniqueKeysWithValues: allIdols.map { ($0.id, $0) })
                }
            }
            .trackScreen("song_edit")
        }
    }

    @ViewBuilder
    private var artistSection: some View {
        ImasListSection("歌唱アイドル",
                        footer: "一覧でアイコンを出すために必要です。ソロ曲なら 1 名、ユニット曲なら全員を選んでください。") {
            Button {
                showArtistPicker = true
            } label: {
                // ImasNavRow は value を 1 行に固定するため使わない。全体曲は選んだ名前が
                // 1 行に収まらないので、ImasRow 直書きで題の行数を広げて全員を折り返す
                // (616eb4a3 の EventEditView/SetlistEditView と同じ形)。
                ImasRow(
                    title: artistIdolIds.isEmpty ? "選択" : artistNames(),
                    leading: .icon("person.2", tone: .neutral),
                    trailing: .chevron,
                    density: .compact,
                    titleLineLimit: 99,
                    titleRole: .rowLabel
                )
            }
            .buttonStyle(.imasRow)
        }
    }

    private func artistNames() -> String {
        artistIdolIds
            .compactMap { idolById[$0]?.name }
            .sorted()
            .joined(separator: " / ")
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "タイトルを入力してください"
            return
        }
        // appleMusicId を設定するなら artworkUrl 必須 (一覧ジャケ写は songs.artwork_url 直参照)。
        // MEMORY: feedback_song_artwork_required。RedTeam Medium に従い警告ではなくブロック。
        let trimmedAmId = appleMusicId.trimmingCharacters(in: .whitespaces)
        if !trimmedAmId.isEmpty && artworkUrl.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "Apple Music ID を設定する場合は artwork URL も必須です (一覧のジャケ写表示に使います)"
            return
        }
        // 新規作成は歌唱アイドル必須 (一覧アイコンの根拠データ)。
        if mode.isCreate && artistIdolIds.isEmpty {
            errorMessage = "歌唱アイドルを 1 名以上選択してください"
            return
        }
        // リリース日はサーバ validator (YYYY-MM-DD) と一致する形式のみ許可。
        let trimmedReleaseDate = releaseDate.trimmingCharacters(in: .whitespaces)
        let trimmedStreamingDate = streamingDate.trimmingCharacters(in: .whitespaces)
        let trimmedCdReleaseDate = cdReleaseDate.trimmingCharacters(in: .whitespaces)
        for (label, value) in [("初出", trimmedReleaseDate), ("CD 発売日", trimmedCdReleaseDate),
                               ("配信開始日", trimmedStreamingDate)]
        where !value.isEmpty && !isValidISODate(value) {
            errorMessage = "\(label)は YYYY-MM-DD 形式で入力してください"
            return
        }
        // 再生時間は秒数 (非負整数) のみ許可。
        let trimmedDuration = durationSecText.trimmingCharacters(in: .whitespaces)
        let parsedDuration = Int(trimmedDuration)
        if !trimmedDuration.isEmpty && (parsedDuration ?? -1) < 0 {
            errorMessage = "再生時間は秒数 (整数) で入力してください"
            return
        }

        // create はクライアント採番 (SongArtist が同一 batch で songId を参照できるように)。
        let songId = mode.original?.id ?? "song_\(UUID().uuidString.lowercased())"

        // update はサーバ側マージセマンティクス: 値を送れば上書き、null 明示送信でクリア、
        // 未送信は現状維持。AnyEncodable.clearable が「空 & 元値あり → null」を担う
        // (「Apple Music 関連を全て空にする」等のクリア操作を CloudKit にも反映するため)。
        let original = mode.original
        var songFields: [String: AnyEncodable] = [
            "title": AnyEncodable(trimmedTitle),
            "songType": AnyEncodable(songType),
        ]
        let resolvedBrandId = brandId.isEmpty ? nil : brandId
        songFields["brandId"] = AnyEncodable.clearable(brandId, original: original?.brandId)
        songFields["titleKana"] = AnyEncodable.clearable(titleKana, original: original?.titleKana)
        songFields["appleMusicId"] = AnyEncodable.clearable(trimmedAmId, original: original?.appleMusicId)
        songFields["appleMusicAlbumId"] = AnyEncodable.clearable(appleMusicAlbumId, original: original?.appleMusicAlbumId)
        songFields["artworkUrl"] = AnyEncodable.clearable(artworkUrl, original: original?.artworkUrl)
        songFields["previewUrl"] = AnyEncodable.clearable(previewUrl, original: original?.previewUrl)
        songFields["cdSeries"] = AnyEncodable.clearable(cdSeries, original: original?.cdSeries)
        songFields["cdTitle"] = AnyEncodable.clearable(cdTitle, original: original?.cdTitle)
        songFields["lyricsUrl"] = AnyEncodable.clearable(lyricsUrl, original: original?.lyricsUrl)
        songFields["unitName"] = AnyEncodable.clearable(unitName, original: original?.unitName)
        songFields["lyricist"] = AnyEncodable.clearable(lyricist, original: original?.lyricist)
        songFields["composer"] = AnyEncodable.clearable(composer, original: original?.composer)
        songFields["arranger"] = AnyEncodable.clearable(arranger, original: original?.arranger)
        songFields["releaseDate"] = AnyEncodable.clearable(trimmedReleaseDate, original: original?.releaseDate)
        songFields["streamingDate"] = AnyEncodable.clearable(trimmedStreamingDate, original: original?.streamingDate)
        songFields["cdReleaseDate"] = AnyEncodable.clearable(trimmedCdReleaseDate, original: original?.cdReleaseDate)
        songFields["singerLabel"] = AnyEncodable.clearable(singerLabel, original: original?.singerLabel)
        songFields["note"] = AnyEncodable.clearable(note, original: original?.note)
        songFields["isrc"] = AnyEncodable.clearable(isrc, original: original?.isrc)
        if let v = parsedDuration {
            songFields["durationSec"] = AnyEncodable(v)
        } else if original?.durationSec != nil {
            songFields["durationSec"] = .null
        }

        var ops: [EditService.EditOperation] = [
            EditService.EditOperation(
                op: mode.isCreate ? .create : .update,
                recordType: "Song",
                recordName: songId,
                fields: songFields
            )
        ]

        // 新規作成時のみ SongArtist(role=original) を同一 batch で create。
        if mode.isCreate {
            for idolId in artistIdolIds {
                // recordName 規約は seed と同じ "song_artists-<songId>-<idolId>-<role>"。
                let recordName = "song_artists-\(songId)-\(idolId)-original"
                ops.append(EditService.EditOperation(
                    op: .create,
                    recordType: "SongArtist",
                    recordName: recordName,
                    fields: [
                        "songId": AnyEncodable(songId),
                        "idolId": AnyEncodable(idolId),
                        "role": AnyEncodable("original"),
                    ]
                ))
            }
        }

        do {
            let outcome = try await EditService.shared.submitMaster(ops: ops, summary: mode.isCreate ? "曲を追加" : "曲編集")
            switch outcome {
            case .applied(let resp):
                // Song は ops[0]。ローカル upsert はサーバ確定 recordName を使う (契約 #3)。
                let resolvedId = resp.primaryRecordName(fallback: songId) ?? songId
                let savedSong = buildSong(id: resolvedId, brandId: resolvedBrandId, amId: trimmedAmId)
                try await AppContainer.shared.songWriting.upsertSongs([savedSong])
                if mode.isCreate {
                    let artists = artistIdolIds.map { SongArtist(songId: resolvedId, idolId: $0, role: "original") }
                    try await AppContainer.shared.songWriting.upsertSongArtists(artists)
                }
                Logger.database.notice("song_\(mode.isCreate ? "created" : "edited", privacy: .public) id=\(resolvedId, privacy: .public)")
                dismiss()
            case .requested:
                requestSent = true
            }
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
        }
    }

    /// 送信値から確定 Song モデルを組む (新規は既定値、編集は original を基に上書き)。
    /// フォームに無いフィールド (parentSongId / unitId) は original の値をそのまま引き継ぎ、
    /// フォームにあるフィールドは全て form の値で確定する (サーバ側マージと同じ結果になる)。
    private func buildSong(id: String, brandId: String?, amId: String) -> Song {
        var song = mode.original ?? Song(
            id: id,
            title: title,
            titleKana: nil,
            brandId: nil,
            songType: songType,
            releaseDate: nil,
            durationSec: nil,
            composer: nil,
            lyricist: nil,
            arranger: nil,
            cdSeries: nil,
            cdTitle: nil,
            artworkUrl: nil,
            previewUrl: nil,
            appleMusicId: nil,
            appleMusicAlbumId: nil,
            isrc: nil,
            lyricsUrl: nil,
            parentSongId: nil,
            singerLabel: nil,
            unitName: nil,
            unitId: nil
        )
        song.id = id
        song.title = title.trimmingCharacters(in: .whitespaces)
        song.titleKana = nonEmpty(titleKana)
        song.brandId = brandId
        song.songType = songType
        song.appleMusicId = amId.isEmpty ? nil : amId
        song.appleMusicAlbumId = nonEmpty(appleMusicAlbumId)
        song.artworkUrl = nonEmpty(artworkUrl)
        song.previewUrl = nonEmpty(previewUrl)
        song.cdSeries = nonEmpty(cdSeries)
        song.cdTitle = nonEmpty(cdTitle)
        song.lyricsUrl = nonEmpty(lyricsUrl)
        song.unitName = nonEmpty(unitName)
        song.lyricist = nonEmpty(lyricist)
        song.composer = nonEmpty(composer)
        song.arranger = nonEmpty(arranger)
        song.releaseDate = nonEmpty(releaseDate)
        song.streamingDate = nonEmpty(streamingDate)
        song.cdReleaseDate = nonEmpty(cdReleaseDate)
        song.singerLabel = nonEmpty(singerLabel)
        song.note = nonEmpty(note)
        song.isrc = nonEmpty(isrc)
        song.durationSec = Int(durationSecText.trimmingCharacters(in: .whitespaces))
        return song
    }

    /// trim 後に空なら nil、それ以外は trim 済み文字列。
    private func nonEmpty(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// YYYY-MM-DD の最小限の妥当性チェック (サーバ validator の ISO_DATE_RE と整合)。
    private func isValidISODate(_ s: String) -> Bool {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4, Int(parts[0]) != nil,
              parts[1].count == 2, let m = Int(parts[1]), (1...12).contains(m),
              parts[2].count == 2, let d = Int(parts[2]), (1...31).contains(d) else {
            return false
        }
        return true
    }
}
