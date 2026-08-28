package com.fugaif.imaslivedb.data.sync

import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolBrand
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.SetlistItem
import com.fugaif.imaslivedb.data.model.SetlistPerformer
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.ShowCast
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongArtist
import com.fugaif.imaslivedb.data.model.SongCall
import com.fugaif.imaslivedb.data.model.SongVideo
import com.fugaif.imaslivedb.data.model.UnitMember
import com.fugaif.imaslivedb.data.model.Venue
import com.fugaif.imaslivedb.data.model.VenueHall
import com.fugaif.imaslivedb.data.model.Creator
import com.fugaif.imaslivedb.data.model.UnitVersion
import com.fugaif.imaslivedb.data.model.VenueName
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.CkField
import uniffi.imas_core.CkIngestBatch
import uniffi.imas_core.CkRow
import uniffi.imas_core.CkValue
import uniffi.imas_core.ckIngestWebServicesBatch
import uniffi.imas_core.ckRecordFromWebServicesJson

/**
 * CloudKit のレコード → Room エンティティ変換。
 *
 * 変換規則そのものは共有コア (`domain::ck_record_mapping`) が持ち、ここは
 * 「CKWS の生レコード JSON を渡して、返ってきた行を Room の data class に詰め替える」
 * 配線だけを担う。iOS の `CKRecordMapper` と同じ規則がコア 1 か所で効くので、
 * 「Android だけ seriesGroup を読み落として NULL 上書きする」類の乖離が起きない。
 *
 * **レコードの `fields` を `value` だけに平坦化してはいけない。** CKWS は
 * TIMESTAMP / INT64 / DOUBLE をどれも JSON の数値で送るため、型を落とすと
 * `deletedAt` が日付と認識されず soft delete が伝搬しなくなり、投稿の `createdAt` も
 * 同期のたび現在時刻に書き換わる。だから [CloudKitClient] は生 JSON のまま返し、
 * 型の振り分けはコア側 (`ck_record_from_web_services_json`) に任せている。
 */
object SyncMappers {

    /**
     * 1 recordType 分のページを「upsert する行 / 削除する recordName / 捨てた recordName」に
     * 仕分ける。取り込み対象外の recordType では空のバッチが返る。
     *
     * FFI 呼び出しは呼び元スレッドをブロックし、1 ステップで数千件の JSON を読むので
     * Default へ逃がす (sync() は UI スコープから呼ばれる)。
     *
     * @param nowMillis SongCall / SongVideo の createdAt 欠損時の既定値。
     *   コアは OS 時刻を取らないので呼び出し側が渡す。
     */
    suspend fun ingest(recordType: String, recordJsons: List<String>, nowMillis: Long): CkIngestBatch =
        withContext(Dispatchers.Default) { ckIngestWebServicesBatch(recordType, recordJsons, nowMillis) }

    /** 単一 PK テーブルの行 ID (孤児掃除の valid_ids 用)。複合 PK の行は ID を持たないので落ちる。 */
    fun rowIds(rows: List<CkRow>): List<String> = rows.mapNotNull { row ->
        when (row) {
            is CkRow.Brand -> row.row.id
            is CkRow.Idol -> row.row.id
            is CkRow.Event -> row.row.id
            is CkRow.Show -> row.row.id
            is CkRow.Song -> row.row.id
            is CkRow.Unit -> row.row.id
            is CkRow.SetlistItem -> row.row.id
            is CkRow.SongCall -> row.row.id
            is CkRow.SongVideo -> row.row.id
            is CkRow.Venue -> row.row.id
            is CkRow.VenueName -> row.row.id
            is CkRow.VenueHall -> row.row.id
            else -> null
        }
    }

    fun brands(rows: List<CkRow>): List<Brand> =
        rows.filterIsInstance<CkRow.Brand>().map { (row) ->
            // コアの iconUrl は捨てる。Brand に列を足すには schema bump が要るのに、
            // master.sqlite の brands にも icon_url は無く (iOS が migration で足して
            // CloudKit からだけ埋める列)、Android にはブランドアイコンを出す画面も無い。
            // 表示の当てが出来たときに Venue と同じ手順で足す。
            Brand(row.id, row.name, row.shortName, row.color.emptyToNull(), row.sortOrder.toInt())
        }

    /**
     * @param voiceActorsById [voiceActorsById] が返す「行に載らない CV 列」。
     *   コアの CkIdolRow は `voiceActors` を意図的に読まない (声優は期間つき履歴が正) が、
     *   Android の upsert は行を丸ごと REPLACE するので、ここで補わないと同期のたび
     *   `idols.voice_actors` が NULL になり CV 表示が消える。
     */
    fun idols(rows: List<CkRow>, voiceActorsById: Map<String, String>): List<Idol> =
        rows.filterIsInstance<CkRow.Idol>().map { (row) ->
            Idol(
                id = row.id,
                brandId = row.brandId,
                name = row.name,
                nameKana = row.nameKana.emptyToNull(),
                nameRomaji = row.nameRomaji.emptyToNull(),
                familyName = row.familyName.emptyToNull(),
                givenName = row.givenName.emptyToNull(),
                nickname = row.nickname.emptyToNull(),
                color = row.color.emptyToNull(),
                sortOrder = row.sortOrder.toInt(),
                birthday = row.birthday.emptyToNull(),
                bloodType = row.bloodType.emptyToNull(),
                height = row.height,
                weight = row.weight,
                birthPlace = row.birthPlace.emptyToNull(),
                age = row.age?.toInt(),
                bust = row.bust,
                waist = row.waist,
                hip = row.hip,
                constellation = row.constellation.emptyToNull(),
                hobbies = row.hobbies.emptyToNull(),
                talents = row.talents.emptyToNull(),
                description = row.description.emptyToNull(),
                gender = row.gender.emptyToNull(),
                handedness = row.handedness.emptyToNull(),
                debutDate = row.debutDate.emptyToNull(),
                attribute = row.attribute.emptyToNull(),
                isExternal = row.isExternal,
                aliases = row.aliases.emptyToNull(),
                voiceActors = voiceActorsById[row.id]
            )
        }

    /**
     * Idol レコードの `voiceActors` を「コアが id を決めるのと同じ規則」で引き当てる。
     *
     * 生 JSON から自前で拾わずコアの射影 ([ckRecordFromWebServicesJson]) を通すのは、
     * CKWS の `type` 振り分けを Kotlin で書き直さないため。id の解決 (STRING の `id`
     * フィールドがあればそれ、無ければ recordName) もコアと同じにしてある。
     *
     * ここだけはレコード 1 件ごとに FFI を跨ぐ (Idol ステップで約 400 回)。ページ全体を
     * 一括射影して返すコア API がまだ無く、Kotlin 側で拾い直すと id 解決規則の二重実装に
     * なるため、規則をコアに寄せる方を優先している。コアにバッチ射影が生えたら 1 回に畳める。
     */
    suspend fun voiceActorsById(recordJsons: List<String>): Map<String, String> =
        withContext(Dispatchers.Default) {
            val out = HashMap<String, String>(recordJsons.size)
            for (json in recordJsons) {
                val record = ckRecordFromWebServicesJson(json)
                // キー重複は後勝ち (コアの Fields と同じ)。
                val id = record.fields.lastOrNull { it.key == "id" }.textValue() ?: record.recordName
                val voiceActors = record.fields.lastOrNull { it.key == "voiceActors" }.textValue()
                if (!voiceActors.isNullOrEmpty()) out[id] = voiceActors
            }
            out
        }

    private fun CkField?.textValue(): String? =
        (this?.value as? CkValue.Text)?.value

    /**
     * 空文字を null に潰す。**任意 (nullable) 列にだけ掛ける。**
     *
     * コアの `str` は iOS の `as? String` に合わせて空文字を保持する (iOS が正) が、
     * Android の旧 `CkRecord.str()` は "" を null にしていた。Room の任意列に "" が入ると
     * 「値がある」と読む消費側が壊れる: [com.fugaif.imaslivedb.ui.components.ArtworkImage] は
     * `previewUrl != null` で再生ボタンを出すので、実データにある songs.preview_url='' の
     * 37 件で「押しても鳴らないボタン」が出る (artwork_url='' は空 URL で読み込み失敗)。
     * seed_cloudkit は NULL しか落とさないため空文字はそのまま CKWS に載ってくる。
     *
     * 変換規則そのものはコア (iOS 準拠) のまま動かさず、Android の列表現だけここで戻す。
     */
    private fun String?.emptyToNull(): String? = this?.takeIf { it.isNotEmpty() }

    fun events(rows: List<CkRow>): List<Event> =
        rows.filterIsInstance<CkRow.Event>().map { (row) ->
            Event(
                id = row.id,
                brandId = row.brandId.emptyToNull(),
                name = row.name,
                eventType = row.eventType,
                isStreaming = row.isStreaming,
                isSolo = row.isSolo,
                kind = row.kind,
                ticketOpenDate = row.ticketOpenDate.emptyToNull(),
                ticketDeadline = row.ticketDeadline.emptyToNull(),
                ticketLotteryDate = row.ticketLotteryDate.emptyToNull(),
                ticketUrl = row.ticketUrl.emptyToNull(),
                jointBrandIds = row.jointBrandIds.emptyToNull()
            )
        }

    fun shows(rows: List<CkRow>): List<Show> =
        rows.filterIsInstance<CkRow.Show>().map { (row) ->
            Show(
                id = row.id,
                eventId = row.eventId,
                name = row.name,
                date = row.date,
                venue = row.venue.emptyToNull(),
                venueId = row.venueId.emptyToNull(),
                hall = row.hall.emptyToNull(),
                streamPlatform = row.streamPlatform.emptyToNull(),
                venueCity = row.venueCity.emptyToNull(),
                startTime = row.startTime.emptyToNull(),
                sortOrder = row.sortOrder.toInt(),
                performerType = row.performerType.emptyToNull()
            )
        }

    /**
     * 会場マスタ。Show より前に取り込む (shows.venue_id が参照する)。
     *
     * 名前ではなく ID で同一性を持たせているので、改名した会場 (武蔵野の森総合スポーツプラザ
     * → 京王アリーナTOKYO) でも履歴が分断されない。当時名は [venueNames] 側。
     */
    fun venues(rows: List<CkRow>): List<Venue> =
        rows.filterIsInstance<CkRow.Venue>().map { (row) ->
            Venue(
                id = row.id,
                name = row.name,
                nameKana = row.nameKana.emptyToNull(),
                prefecture = row.prefecture.emptyToNull(),
                city = row.city.emptyToNull(),
                aliases = row.aliases.emptyToNull(),
                capacity = row.capacity?.toInt(),
                sortOrder = row.sortOrder.toInt()
            )
        }

    /**
     * 改名履歴。有効期間は空文字ではなく null に潰す:
     * [com.fugaif.imaslivedb.data.model.VenueName.isValidOn] は文字列比較で期間を判定するので、
     * validTo="" だと `date >= ""` が常に真になり、その名前が一度も有効にならなくなる。
     */
    /** 作詞・作曲・編曲の表記とその読み。 */
    fun creators(rows: List<CkRow>): List<Creator> =
        rows.filterIsInstance<CkRow.Creator>().map { (row) ->
            Creator(id = row.id, name = row.name, nameKana = row.nameKana,
                    aliases = row.aliases.emptyToNull())
        }

    /**
     * ユニットの版 (Project“ReLight”AXE8 等)。
     *
     * ユニット自体は 1 行のまま。版で分かれるのは曲側 (songs.unit_version_id)。
     */
    fun unitVersions(rows: List<CkRow>): List<UnitVersion> =
        rows.filterIsInstance<CkRow.UnitVersion>().map { (row) ->
            UnitVersion(
                id = row.id,
                unitId = row.unitId,
                code = row.code.emptyToNull(),
                name = row.name,
                catchphrase = row.catchphrase.emptyToNull(),
                logoUrl = row.logoUrl.emptyToNull(),
                validFrom = row.validFrom.emptyToNull(),
                validTo = row.validTo.emptyToNull(),
                sortOrder = row.sortOrder.toInt()
            )
        }

    fun venueNames(rows: List<CkRow>): List<VenueName> =
        rows.filterIsInstance<CkRow.VenueName>().map { (row) ->
            VenueName(row.id, row.venueId, row.name, row.validFrom.emptyToNull(), row.validTo.emptyToNull())
        }

    fun venueHalls(rows: List<CkRow>): List<VenueHall> =
        rows.filterIsInstance<CkRow.VenueHall>().map { (row) ->
            VenueHall(row.id, row.venueId, row.name, row.capacity?.toInt())
        }

    fun songs(rows: List<CkRow>): List<Song> =
        rows.filterIsInstance<CkRow.Song>().map { (row) ->
            Song(
                id = row.id,
                title = row.title,
                titleKana = row.titleKana.emptyToNull(),
                brandId = row.brandId.emptyToNull(),
                songType = row.songType,
                releaseDate = row.releaseDate.emptyToNull(),
                durationSec = row.durationSec?.toInt(),
                composer = row.composer.emptyToNull(),
                lyricist = row.lyricist.emptyToNull(),
                arranger = row.arranger.emptyToNull(),
                cdSeries = row.cdSeries.emptyToNull(),
                cdTitle = row.cdTitle.emptyToNull(),
                artworkUrl = row.artworkUrl.emptyToNull(),
                previewUrl = row.previewUrl.emptyToNull(),
                appleMusicId = row.appleMusicId.emptyToNull(),
                appleMusicAlbumId = row.appleMusicAlbumId.emptyToNull(),
                isrc = row.isrc.emptyToNull(),
                lyricsUrl = row.lyricsUrl.emptyToNull(),
                parentSongId = row.parentSongId.emptyToNull(),
                singerLabel = row.singerLabel.emptyToNull(),
                unitName = row.unitName.emptyToNull(),
                unitId = row.unitId.emptyToNull(),
                seriesGroup = row.seriesGroup.emptyToNull(),
                // 読み落とすと、同期のたびに版つきの曲 (sc_beam / sc_iwe) が無印へ戻る。
                unitVersionId = row.unitVersionId.emptyToNull()
            )
        }

    fun units(rows: List<CkRow>): List<ImasUnit> =
        rows.filterIsInstance<CkRow.Unit>().map { (row) ->
            ImasUnit(
                row.id, row.brandId, row.name, row.isPermanent,
                row.nameAlt.emptyToNull(), row.nameKana.emptyToNull()
            )
        }

    fun idolBrands(rows: List<CkRow>): List<IdolBrand> =
        rows.filterIsInstance<CkRow.IdolBrand>().map { (row) ->
            IdolBrand(row.idolId, row.brandId, row.isPrimary)
        }

    fun unitMembers(rows: List<CkRow>): List<UnitMember> =
        rows.filterIsInstance<CkRow.UnitMember>().map { (row) -> UnitMember(row.unitId, row.idolId) }

    fun songArtists(rows: List<CkRow>): List<SongArtist> =
        rows.filterIsInstance<CkRow.SongArtist>().map { (row) ->
            SongArtist(row.songId, row.idolId, row.role)
        }

    fun showCasts(rows: List<CkRow>): List<ShowCast> =
        rows.filterIsInstance<CkRow.ShowCast>().map { (row) ->
            ShowCast(row.showId, row.idolId, row.castRole)
        }

    fun setlistItems(rows: List<CkRow>): List<SetlistItem> =
        rows.filterIsInstance<CkRow.SetlistItem>().map { (row) ->
            SetlistItem(
                row.id, row.showId, row.songId, row.position.toInt(),
                row.section.emptyToNull(), row.notes.emptyToNull(), row.unitName.emptyToNull()
            )
        }

    fun setlistPerformers(rows: List<CkRow>): List<SetlistPerformer> =
        rows.filterIsInstance<CkRow.SetlistPerformer>().map { (row) ->
            SetlistPerformer(row.setlistItemId, row.idolId)
        }

    fun songCalls(rows: List<CkRow>): List<SongCall> =
        rows.filterIsInstance<CkRow.SongCall>().map { (row) ->
            SongCall(
                row.id, row.songId, row.callText, row.sourceUrl.emptyToNull(),
                row.createdAt, row.authorDisplayName.emptyToNull()
            )
        }

    fun songVideos(rows: List<CkRow>): List<SongVideo> =
        rows.filterIsInstance<CkRow.SongVideo>().map { (row) ->
            SongVideo(
                row.id, row.songId, row.youtubeUrl, row.videoTitle.emptyToNull(), row.note.emptyToNull(),
                row.createdAt, row.authorDisplayName.emptyToNull()
            )
        }
}
