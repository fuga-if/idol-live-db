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

/**
 * CkRecord → Room エンティティ変換。iOS の CKRecordMapper と同じフィールド名・規約。
 * 必須キーが欠ける不正レコードは null を返してスキップする。
 */
object SyncMappers {

    private fun id(r: CkRecord): String? = (r.str("id") ?: r.recordName).takeIf { it.isNotEmpty() }

    fun brand(r: CkRecord): Brand? {
        val id = id(r) ?: return null
        val name = r.str("name") ?: return null
        return Brand(id, name, r.str("shortName") ?: "", r.str("color"), r.int("sortOrder"))
    }

    fun idol(r: CkRecord): Idol? {
        val id = id(r) ?: return null
        val name = r.str("name") ?: return null
        return Idol(
            id = id,
            brandId = r.str("brandId") ?: "",
            name = name,
            nameKana = r.str("nameKana"),
            nameRomaji = r.str("nameRomaji"),
            color = r.str("color"),
            sortOrder = r.int("sortOrder"),
            birthday = r.str("birthday"),
            bloodType = r.str("bloodType"),
            height = r.double("height"),
            weight = r.double("weight"),
            birthPlace = r.str("birthPlace"),
            age = r.intOrNull("age"),
            bust = r.double("bust"),
            waist = r.double("waist"),
            hip = r.double("hip"),
            constellation = r.str("constellation"),
            hobbies = r.str("hobbies"),
            talents = r.str("talents"),
            description = r.str("description"),
            gender = r.str("gender"),
            handedness = r.str("handedness")
        )
    }

    fun event(r: CkRecord): Event? {
        val id = id(r) ?: return null
        val name = r.str("name") ?: return null
        return Event(id, r.str("brandId"), name, r.str("eventType") ?: "live", r.bool("isStreaming"))
    }

    fun show(r: CkRecord): Show? {
        val id = id(r) ?: return null
        val eventId = r.str("eventId") ?: return null
        val date = r.str("date") ?: return null
        return Show(
            id = id,
            eventId = eventId,
            name = r.str("name") ?: "",
            date = date,
            venue = r.str("venue"),
            venueCity = r.str("venueCity"),
            startTime = r.str("startTime"),
            sortOrder = r.int("sortOrder"),
            performerType = r.str("performerType")
        )
    }

    fun song(r: CkRecord): Song? {
        val id = id(r) ?: return null
        val title = r.str("title") ?: return null
        return Song(
            id = id,
            title = title,
            titleKana = r.str("titleKana"),
            brandId = r.str("brandId"),
            songType = r.str("songType") ?: "solo",
            releaseDate = r.str("releaseDate"),
            durationSec = r.intOrNull("durationSec"),
            composer = r.str("composer"),
            lyricist = r.str("lyricist"),
            arranger = r.str("arranger"),
            cdSeries = r.str("cdSeries"),
            cdTitle = r.str("cdTitle"),
            artworkUrl = r.str("artworkUrl"),
            previewUrl = r.str("previewUrl"),
            appleMusicId = r.str("appleMusicId"),
            appleMusicAlbumId = r.str("appleMusicAlbumId"),
            isrc = r.str("isrc"),
            lyricsUrl = r.str("lyricsUrl"),
            parentSongId = r.str("parentSongId"),
            singerLabel = r.str("singerLabel"),
            unitName = r.str("unitName"),
            unitId = r.str("unitId")
        )
    }

    fun unit(r: CkRecord): ImasUnit? {
        val id = id(r) ?: return null
        val name = r.str("name") ?: return null
        return ImasUnit(id, r.str("brandId") ?: "", name, r.bool("isPermanent", default = true), r.str("nameAlt"))
    }

    fun idolBrand(r: CkRecord): IdolBrand? {
        val idolId = r.str("idolId") ?: return null
        val brandId = r.str("brandId") ?: return null
        return IdolBrand(idolId, brandId, r.bool("isPrimary"))
    }

    fun unitMember(r: CkRecord): UnitMember? {
        val unitId = r.str("unitId") ?: return null
        val idolId = r.str("idolId") ?: return null
        return UnitMember(unitId, idolId)
    }

    fun songArtist(r: CkRecord): SongArtist? {
        val songId = r.str("songId") ?: return null
        val idolId = r.str("idolId") ?: return null
        return SongArtist(songId, idolId, r.str("role") ?: "original")
    }

    fun showCast(r: CkRecord): ShowCast? {
        val showId = r.str("showId") ?: return null
        val idolId = r.str("idolId") ?: return null
        return ShowCast(showId, idolId, r.str("castRole"))
    }

    fun setlistItem(r: CkRecord): SetlistItem? {
        val id = id(r) ?: return null
        val showId = r.str("showId") ?: return null
        val songId = r.str("songId") ?: return null
        return SetlistItem(id, showId, songId, r.int("position"), r.str("section"), r.str("notes"), r.str("unitName"))
    }

    fun setlistPerformer(r: CkRecord): SetlistPerformer? {
        val setlistItemId = r.str("setlistItemId") ?: return null
        val idolId = r.str("idolId") ?: return null
        return SetlistPerformer(setlistItemId, idolId)
    }

    fun songCall(r: CkRecord): SongCall? {
        val songId = r.str("songId") ?: return null
        val callText = r.str("callText") ?: return null
        return SongCall(r.recordName, songId, callText, r.str("sourceUrl"), r.str("createdAt"), r.str("authorDisplayName"))
    }

    fun songVideo(r: CkRecord): SongVideo? {
        val songId = r.str("songId") ?: return null
        val youtubeUrl = r.str("youtubeUrl") ?: return null
        return SongVideo(r.recordName, songId, youtubeUrl, r.str("videoTitle"), r.str("note"), r.str("createdAt"), r.str("authorDisplayName"))
    }
}
