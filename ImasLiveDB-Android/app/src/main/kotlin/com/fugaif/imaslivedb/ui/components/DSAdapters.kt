package com.fugaif.imaslivedb.ui.components

import android.net.Uri
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.image.CustomImageStore
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasBrandOption
import com.fugaif.imaslivedb.ui.designsystem.ImasBrandPicker
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolCell
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowEmphasis
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSongRow

// =============================================================================
// アプリのモデルから DesignSystem の部品へ写す口 (iOS `Views/Components/DSAdapters.swift` の移植)。
//
// DesignSystem はアプリのサービス (試聴の再生・取り込んだブランドのロゴなど) を知らない。
// 画像の在り処や再生の配線のようなアプリ側の事情はここで 1 回だけ解決し、画面は部品にモデルを渡すだけにする。
// =============================================================================

// MARK: - ブランド

/** ブランドから (iOS `ImasBrandPicker.Option(brand:)`)。読み込んだロゴがあればロゴ、無ければペンライト。 */
fun ImasBrandOption(brand: Brand, store: CustomImageStore): ImasBrandOption =
    ImasBrandOption(id = brand.id, label = brand.shortName, color = brand.color, logo = store.brandImageFile(brand.id))

/**
 * ブランドの並びから組む (iOS `ImasBrandPicker(brands:selection:)`)。
 * ロゴの取り込み・削除はその場で反映する (取り込んだブランドの集合を購読する)。
 */
@Composable
fun ImasBrandPicker(
    brands: List<Brand>,
    selection: Set<String>,
    onSelectionChange: (Set<String>) -> Unit,
    modifier: Modifier = Modifier,
    includesAll: Boolean = true,
    allLabel: String = "全て",
    allowsMultiple: Boolean = true
) {
    val store = AppModule.from(LocalContext.current).customImageStore
    val withImages by store.brandsWithImages.collectAsState()
    val version by store.galleryVersion.collectAsState()
    val options = remember(brands, withImages, version) { brands.map { ImasBrandOption(it, store) } }
    ImasBrandPicker(
        options = options,
        selection = selection,
        onSelectionChange = onSelectionChange,
        modifier = modifier,
        includesAll = includesAll,
        allLabel = allLabel,
        allowsMultiple = allowsMultiple
    )
}

// MARK: - 曲

/** 試聴に使える URL (http/https でホストがあるものだけ。iOS `URL.safeHTTP`)。 */
private fun safeHttp(url: String?): String? {
    if (url.isNullOrEmpty()) return null
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return null
    val scheme = uri.scheme?.lowercase()
    return url.takeIf { (scheme == "https" || scheme == "http") && !uri.host.isNullOrEmpty() }
}

/**
 * 曲のデータから組む (iOS `ImasSongRow(song:)`)。副題は既定でユニット名 (無ければ歌唱者の表記)。
 * ジャケの試聴を自動で持つ (楽曲一覧の行と同じ配線)。
 *
 * @param playsPreview false で試聴だけ切る (ジャケを押しても行全体のタップが効く。集計の行など、
 *   ジャケを押すたびに詳細が開いてほしい画面で使う)。
 * @param detail 下段 (札・日付)。
 */
@Composable
fun ImasSongRow(
    song: Song,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    showsBrandBar: Boolean = false,
    playsPreview: Boolean = true,
    trailing: ImasRowTrailing = ImasRowTrailing.None,
    density: ImasRowDensity = ImasRowDensity.REGULAR,
    emphasis: ImasRowEmphasis = ImasRowEmphasis.NORMAL,
    onClick: (() -> Unit)? = null,
    detail: (@Composable ColumnScope.() -> Unit)? = null
) {
    val previewUrl = if (playsPreview) remember(song.previewUrl) { safeHttp(song.previewUrl) } else null
    val play = rememberSongRowPlay(song.id, song.appleMusicId, previewUrl)
    ImasSongRow(
        title = song.title,
        modifier = modifier,
        subtitle = subtitle ?: song.unitName ?: song.singerLabel,
        artworkUrl = song.artworkUrl,
        brand = song.brandId,
        showsBrandBar = showsBrandBar,
        previewUrl = previewUrl,
        isPreviewing = previewUrl != null && play.isPlaying,
        onPreviewTap = play.onTap,
        trailing = trailing,
        density = density,
        emphasis = emphasis,
        onClick = onClick,
        detail = detail
    )
}

// MARK: - アイドル

/**
 * アイドルから (iOS `ImasIdolCell(idol:)`)。アイコンは写真を設定した子は写真、無ければ略称の判子。
 * 担当は輪が二重になる。
 *
 * @param metric 並べ替えの値 (何順に並んでいるか)。
 */
@Composable
fun ImasIdolCell(
    idol: Idol,
    isPick: Boolean,
    modifier: Modifier = Modifier,
    metric: String? = null,
    showsKana: Boolean = false,
    isSelected: Boolean? = null
) {
    ImasIdolCell(
        name = idol.name,
        modifier = modifier,
        kana = if (showsKana) idol.nameKana else null,
        seed = idol.color,
        brand = idol.brandId,
        iconLabel = idol.shortName,
        entityId = idol.id,
        isPick = isPick,
        metric = metric,
        isSelected = isSelected
    )
}
