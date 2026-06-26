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
    @State private var singerLabel: String
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

    private let songTypes = ["solo", "unit", "all", "original"]

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
        _singerLabel = State(initialValue: song.singerLabel ?? "")
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
        _singerLabel = State(initialValue: "")
        _isrc = State(initialValue: "")
        _durationSecText = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    if let original = mode.original {
                        LabeledContent("ID") { Text(original.id).foregroundStyle(DS.ink2) }
                    }
                    TextField("タイトル", text: $title)
                    TextField("タイトル (カナ)", text: $titleKana)
                    Picker("ブランド", selection: $brandId) {
                        Text("未指定").tag("")
                        ForEach(allBrands) { Text($0.name).tag($0.id) }
                    }
                    Picker("種別", selection: $songType) {
                        ForEach(songTypes, id: \.self) { Text(songTypeLabel($0)).tag($0) }
                    }
                    TextField("ユニット名", text: $unitName)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                if mode.isCreate {
                    artistSection
                }

                Section("制作情報") {
                    TextField("作詞", text: $lyricist)
                    TextField("作曲", text: $composer)
                    TextField("編曲", text: $arranger)
                    TextField("リリース日 (YYYY-MM-DD)", text: $releaseDate)
                        .keyboardType(.numbersAndPunctuation)
                        .autocapitalization(.none).autocorrectionDisabled()
                    TextField("歌唱表記 (例: 春香・千早)", text: $singerLabel)
                    TextField("再生時間 (秒)", text: $durationSecText)
                        .keyboardType(.numberPad)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section("Apple Music") {
                    TextField("apple_music_id", text: $appleMusicId)
                        .keyboardType(.numberPad)
                    TextField("apple_music_album_id", text: $appleMusicAlbumId)
                        .keyboardType(.numberPad)
                    TextField("artwork URL", text: $artworkUrl)
                        .keyboardType(.URL).autocapitalization(.none).autocorrectionDisabled()
                    TextField("preview URL", text: $previewUrl)
                        .keyboardType(.URL).autocapitalization(.none).autocorrectionDisabled()
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
                Section("CD / その他") {
                    TextField("cd_series", text: $cdSeries)
                    TextField("cd_title", text: $cdTitle)
                    TextField("ISRC", text: $isrc)
                        .autocapitalization(.none).autocorrectionDisabled()
                    TextField("歌詞 URL", text: $lyricsUrl)
                        .keyboardType(.URL).autocapitalization(.none).autocorrectionDisabled()
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
                if !mode.isCreate {
                    Section {
                        Button("Apple Music 関連を全て空にする", role: .destructive) {
                            appleMusicId = ""
                            appleMusicAlbumId = ""
                            artworkUrl = ""
                            previewUrl = ""
                        }
                    } footer: {
                        Text("誤紐付けで他の曲が再生されるときに使う。サブスク未配信の曲はクリアすべき。")
                    }
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle(mode.isCreate ? "曲を追加" : "曲編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { AppAnalytics.tap("song_edit.save"); Task { await save() } }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .overlay { if isSaving { savingOverlay } }
            .alert("エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: { Text(errorMessage ?? "") }
            .sheet(isPresented: $showArtistPicker) {
                IdolMultiPickerView(selected: artistIdolIds, idols: allIdols) { newSelection in
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
        Section {
            Button {
                showArtistPicker = true
            } label: {
                HStack(alignment: .top) {
                    Image(systemName: "person.2")
                        .foregroundStyle(DS.ink2)
                    if artistIdolIds.isEmpty {
                        Text("歌唱アイドルを選択")
                            .foregroundStyle(DS.ink2)
                    } else {
                        Text(artistNames())
                            .font(.imasCallout)
                            .foregroundStyle(DS.ink)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink3)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("歌唱アイドル")
        } footer: {
            Text("一覧でアイコンを出すために必要です。ソロ曲なら 1 名、ユニット曲なら全員を選んでください。")
        }
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    private func artistNames() -> String {
        artistIdolIds
            .compactMap { idolById[$0]?.name }
            .sorted()
            .joined(separator: " / ")
    }

    private func songTypeLabel(_ type: String) -> String {
        switch type {
        case "solo": return "ソロ"
        case "unit": return "ユニット"
        case "all": return "全体曲"
        case "original": return "オリジナル"
        default: return type
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView("保存中…").padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
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
        if !trimmedReleaseDate.isEmpty && !isValidISODate(trimmedReleaseDate) {
            errorMessage = "リリース日は YYYY-MM-DD 形式で入力してください"
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
        songFields["singerLabel"] = AnyEncodable.clearable(singerLabel, original: original?.singerLabel)
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
            let resp = try await EditService.shared.submit(ops: ops, summary: mode.isCreate ? "曲を追加" : "曲編集")
            // Song は ops[0]。ローカル upsert はサーバ確定 recordName を使う
            // (Song は client 採番 UUID なので通常は送信値と一致するが、サーバ権威値に揃える。契約 #3)。
            let resolvedId = resp.primaryRecordName(fallback: songId) ?? songId

            // ローカル楽観更新: Song 本体 + (新規時) SongArtist。SongArtist の songId も確定 ID に揃える。
            let savedSong = buildSong(id: resolvedId, brandId: resolvedBrandId, amId: trimmedAmId)
            try await AppContainer.shared.songWriting.upsertSongs([savedSong])
            if mode.isCreate {
                let artists = artistIdolIds.map { SongArtist(songId: resolvedId, idolId: $0, role: "original") }
                try await AppContainer.shared.songWriting.upsertSongArtists(artists)
            }
            Logger.database.notice("song_\(mode.isCreate ? "created" : "edited", privacy: .public) id=\(resolvedId, privacy: .public)")
            dismiss()
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
        song.singerLabel = nonEmpty(singerLabel)
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
