package com.fugaif.imaslivedb.ui.designsystem

import com.fugaif.imaslivedb.ui.theme.imasStripesVertical
import androidx.compose.ui.draw.drawBehind
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.data.image.GalleryKind
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasPenlight
import com.fugaif.imaslivedb.ui.theme.ImasPenlightSize
import com.fugaif.imaslivedb.ui.theme.ImasRainbow
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.LocalImasColors
import com.fugaif.imaslivedb.ui.theme.hexToColor
import com.fugaif.imaslivedb.ui.theme.imasEnvTheme
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.penlight
import uniffi.imas_core.colorAccessibilityName

// =============================================================================
// 画像と印 (docs/DESIGN_SYSTEM.md §10.3)。iOS `ImasMedia.swift` の移植。
//
// ImasAvatar        アイドルのアイコン。設定した写真があれば写真、無ければ判子 (紙の白 + 実体色の輪と名前)。
//                   担当は輪を二重にする。アイドルを出す所ではいつも出す (目印として読まれている)。
// ImasIconBadge     アイコンの角に重ねる小さな丸い口 (写真を選ぶ「カメラ」)。
// ImasAvatarStack   歌唱者・出演者のアイコンを重ねて並べる。入り切らない人数は「+N」の丸。
// ImasArtwork       曲のジャケ。角のある四角。画像が無ければブランド色の面 + 曲名 (色が分からなければ灰の面 + 音符)。
// ImasIconTile      記号 1 つ。地を敷かない (記号を淡い色の四角に入れない)。
// ImasSwatch        色の丸 (タグの色・ペンライトの色)。読み上げは色名。
// ImasLeadBar       ライブ・公演・アイドルの行頭の細い帯。
// ImasPerformerChip 歌唱者 1 人 (ペンライト + 名前)。欠席は薄字 + 取り消し線。
//
// 色は seed (色 hex) / brand (ブランド ID) を渡せばその色、渡さなければ環境の実体色 (`ImasThemeProvider`)。
// =============================================================================

/**
 * ユーザーが端末に取り込んだカスタム画像 (プライマリ 1 枚) を返す。無ければ null。
 *
 * [com.fugaif.imaslivedb.data.image.CustomImageStore.galleryVersion] を購読しているので、追加・削除・アイコン変更を
 * したその場でアバターが差し替わる (iOS が `galleryVersion` を読んで再描画するのと同じ)。
 * 参照解決自体はメモリキャッシュ済みの manifest を見るだけで、描画中にディスクは読まない。
 */
@Composable
fun rememberCustomImage(entityId: String?, kind: GalleryKind = GalleryKind.IDOL): java.io.File? {
    if (entityId == null) return null
    val store = AppModule.from(LocalContext.current).customImageStore
    val version by store.galleryVersion.collectAsState()
    return remember(entityId, kind, version) { store.primaryImageFile(entityId, kind) }
}

// MARK: - アバター

/** アバターの担当の輪の分の、見えるアイコンと外形の間の片側の余白 (iOS `ImasAvatar.ringPadding`)。 */
val ImasAvatarRingPadding: Dp = 5.5.dp

/**
 * アイドルのアイコン (iOS `ImasAvatar`)。設定した写真があれば写真、無ければ「判子」にする。
 *
 * 判子は紙の白の丸に、実体色の輪と実体色の名前 (詰め組みの太字)。色は輪と文字だけに出す
 * (淡い色の地は敷かない)。担当 ([isPick]) は輪を二重にする (二重丸の判子)。
 * アイドルを出す所 (詳細の頭・名札・行・チップ・セトリの歌唱者) ではいつも出す。写真の有無で消さない。
 *
 * @param brand ブランド ID (アイドル本人の色 [seed] が無いときの色)。
 * @param entityId 渡すと、ユーザーが取り込んだ写真 (あれば) を [imageUrl] より優先して出す。
 *   「誰の」写真かはこの id でしか引けないので、アイドル/ユニットのアバターには必ず渡す。
 * @param reservesPickRing true (既定) のとき、担当の輪の分の外形を [isPick] に関わらず常に確保する
 *   (担当/非担当が混ざる一覧・格子で占める場所を揃えるため)。
 */
@Composable
fun ImasAvatar(
    label: String,
    seed: String? = null,
    brand: String? = null,
    size: Dp = 40.dp,
    isPick: Boolean = false,
    imageUrl: String? = null,
    entityId: String? = null,
    entityKind: GalleryKind = GalleryKind.IDOL,
    modifier: Modifier = Modifier,
    reservesPickRing: Boolean = true
) {
    val t = if (seed != null || brand != null) imasThemeForBrand(seed, brand) else imasEnvTheme
    // ローカル取り込み画像が最優先。File のまま渡せば Coil が file:// として読む。
    val model: Any? = rememberCustomImage(entityId, entityKind) ?: imageUrl
    val outer = if (reservesPickRing) size + ImasAvatarRingPadding * 2 else size
    // 輪の太さ。大きいアイコンほど太く。二重の輪の間も同じ。
    val ringWidth = when {
        size >= 64.dp -> 2.5.dp
        size >= 36.dp -> 1.75.dp
        else -> 1.25.dp
    }
    val ringGap = if (size >= 64.dp) 3.dp else 2.dp
    Box(
        modifier
            .size(outer)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) {
        if (isPick) {
            Box(
                Modifier
                    .size(size + (ringWidth + ringGap) * 2)
                    .border(ringWidth, t.accent, CircleShape)
            )
        }
        Box(
            Modifier
                .size(size)
                .clip(CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (model != null) {
                SubcomposeAsyncImage(
                    model = model,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(size),
                    loading = { AvatarSeal(label, t, size) },
                    error = { AvatarSeal(label, t, size) }
                )
            } else {
                AvatarSeal(label, t, size)
            }
        }
        Box(
            Modifier
                .size(size)
                .border(ringWidth, t.accent, CircleShape)
        )
    }
}

/**
 * 判子。名前はアイコンの大きさに対して決める (文字の大きさの設定で丸からはみ出さないよう固定)。
 * [ImasAvatar] 専用ではなく、`ImasUnitAvatar` (ユニットの名前入りの判子) からも呼ぶ。
 */
@Composable
fun AvatarSeal(label: String, t: ImasTheme, size: Dp) {
    // dp → sp に直してから文字にするので、文字の大きさの設定に関わらず丸に対して同じ割合になる。
    val fontSize = with(LocalDensity.current) { (size * 0.34f).toSp() }
    Box(
        Modifier
            .size(size)
            .background(DS.paper)
            .padding(horizontal = size * 0.1f),
        contentAlignment = Alignment.Center
    ) {
        ImasFitText(
            label,
            style = ImasType.heading(fontSize, FontWeight.Bold),
            color = t.accent,
            minScale = 0.5f,
            textAlign = TextAlign.Center
        )
    }
}

// MARK: - アイコンの角の口

/**
 * アイコンの角に重ねる小さな丸い口 (iOS `ImasIconBadge`。写真を選ぶ「カメラ」など)。
 * 実体の色で塗り、紙の色で縁取る。押す動作は画面が包む (写真を選ぶ起動など)。
 *
 * @param label 読み上げ (「写真を選ぶ」)。null なら読み上げに出さない。
 */
@Composable
fun ImasIconBadge(
    icon: ImageVector,
    modifier: Modifier = Modifier,
    label: String? = null,
    seed: String? = null,
    brand: String? = null,
    size: Dp = 26.dp
) {
    val t = imasThemeForBrand(seed, brand)
    val fill = if (t.isNeutral) DS.sys else t.accent
    val ink = if (t.isNeutral) DS.onSys else t.onAccent
    val glyph = with(LocalDensity.current) { 13.sp.toDp() }
    Box(
        modifier
            .size(size)
            .background(fill, CircleShape)
            .border(2.dp, DS.surface, CircleShape)
            .then(
                if (label != null) Modifier.semantics { contentDescription = label }
                else Modifier.clearAndSetSemantics { }
            ),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.size(glyph))
    }
}

// MARK: - アイコンの重ね

/** [ImasAvatarStack] の読み上げの形。 */
@Immutable
sealed interface ImasAvatarStackSpeech {
    /** 全員の名前を「、」で繋いで読む (既定。セトリの歌唱者など少人数向け)。 */
    data object Names : ImasAvatarStackSpeech

    /** 「<label> N名」で読む (全体曲など大人数の行で、毎行全員を読ませないため)。 */
    data class Count(val label: String) : ImasAvatarStackSpeech
}

/**
 * 歌唱者・出演者のアイコンを少しずつ重ねて並べる (iOS `ImasAvatarStack`。同じ集団の合図)。
 * 入り切らない人数は列の最後に「+N」の丸。この丸は人ではなく注記なので、重ねずに少し離して置く。
 *
 * @param onTap 押したとき (歌唱者の一覧を開く)。null なら押せない (親の行のタップに通す)。
 */
@Composable
fun ImasAvatarStack(
    people: List<ImasPerformer>,
    modifier: Modifier = Modifier,
    maxVisible: Int = 5,
    size: Dp = 26.dp,
    onTap: (() -> Unit)? = null,
    speech: ImasAvatarStackSpeech = ImasAvatarStackSpeech.Names
) {
    val visible = people.take(maxVisible)
    val overflow = people.size - visible.size
    val step = size * 0.6f
    val avatarsWidth = if (visible.isEmpty()) 0.dp else step * (visible.size - 1) + size
    val totalWidth = avatarsWidth + if (overflow > 0) DS.Space.gapTight + size else 0.dp
    val spoken = when (speech) {
        ImasAvatarStackSpeech.Names -> people.joinToString("、") { it.name }
        is ImasAvatarStackSpeech.Count -> "${speech.label} ${people.size}名"
    }
    val surface = DS.surface
    Box(
        modifier
            .width(totalWidth)
            .height(size)
            .then(if (onTap != null) Modifier.clickable(onClick = onTap) else Modifier)
            .clearAndSetSemantics {
                contentDescription = spoken
                if (onTap != null) role = Role.Button
            }
    ) {
        visible.forEachIndexed { index, p ->
            ImasAvatar(
                label = p.iconLabel ?: p.name,
                seed = p.color,
                size = size,
                imageUrl = p.imageUrl,
                entityId = p.entityId,
                reservesPickRing = false,
                modifier = Modifier
                    .offset(x = step * index)
                    .zIndex((maxVisible - index).toFloat())
                    .border(2.dp, surface, CircleShape)
                    .alpha(if (p.isAbsent) 0.4f else 1f)
            )
        }
        if (overflow > 0) {
            Box(
                Modifier
                    .offset(x = avatarsWidth + DS.Space.gapTight)
                    .size(size)
                    .background(DS.fill, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text("+$overflow", style = ImasType.text(11.sp, FontWeight.SemiBold), color = DS.ink2, maxLines = 1)
            }
        }
    }
}

// MARK: - ジャケ

/**
 * 曲のジャケ (iOS `ImasArtwork`)。実画像があれば表示、無ければ面 + 曲名。
 *
 * ジャケが無い曲は、色 (seed / brand) が分かるときは実体色の面 + 曲名 (合同ライブで曲ごとのブランドが
 * 色で分かるのはこれだけが頼りなので、灰に潰さない)。色が分からない実体 (アルバム・シリーズの格子など) は
 * 灰の面 + 記号。
 *
 * 回収は印にしない (ジャケに判子を押さない。回収は下段の札 ✓N。2026-10-02 ユーザーの決まり)。
 * [previewUrl] を渡すと試聴の再生/停止の記号が点き、押すと [onPreview] を呼ぶ (再生状態はアプリ側が [isPreviewing] で渡す)。
 *
 * @param brand ブランド ID。
 * @param isElevated 詳細の頭の大きいジャケ。レコードのスリーブのように紙から浮かせる (影)。
 * @param fallbackIcon 画像も曲名も無いときの記号。曲は音符、円盤など曲以外の実体はそれぞれの記号に替える。
 */
@Composable
fun ImasArtwork(
    title: String,
    seed: String? = null,
    brand: String? = null,
    size: Dp = 48.dp,
    imageUrl: String? = null,
    modifier: Modifier = Modifier,
    isElevated: Boolean = false,
    fallbackIcon: ImageVector = Icons.Filled.MusicNote,
    previewUrl: String? = null,
    isPreviewing: Boolean = false,
    onPreview: (() -> Unit)? = null
) {
    val hasColor = seed != null || brand != null
    val t = if (hasColor) imasThemeForBrand(seed, brand) else imasEnvTheme
    val shape = RoundedCornerShape(DS.rArtwork(size))
    val dark = LocalImasColors.current.dark
    val spoken = if (previewUrl != null) "${title}を試聴" else title
    Box(
        modifier
            .size(size)
            .then(
                if (isElevated) Modifier.imasSoftShadow(
                    shape,
                    fill = DS.surface,
                    color = Color.Black.copy(alpha = if (dark) 0.6f else 0.22f),
                    blur = 15.dp,
                    offsetY = 12.dp
                ) else Modifier
            )
            // 試聴 URL が無いとき (ほぼ全ての呼び出し) は押せる口を付けない。付けると、行全体を押せる行で
            // ジャケの上だけタップが奪われて遷移しなくなる。
            .then(if (previewUrl != null) Modifier.clickable { onPreview?.invoke() } else Modifier)
            .semantics {
                contentDescription = spoken
                if (previewUrl != null) {
                    role = Role.Button
                    stateDescription = if (isPreviewing) "再生中" else "停止中"
                }
            }
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .clip(shape)
                .border(0.5.dp, DS.sep, shape),
            contentAlignment = Alignment.Center
        ) {
            if (imageUrl != null) {
                SubcomposeAsyncImage(
                    model = imageUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                    loading = { ArtworkFallback(title, t, size, hasColor, fallbackIcon) },
                    error = { ArtworkFallback(title, t, size, hasColor, fallbackIcon) }
                )
            } else {
                ArtworkFallback(title, t, size, hasColor, fallbackIcon)
            }
            if (previewUrl != null) {
                if (isPreviewing) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f)))
                Icon(
                    if (isPreviewing) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(maxOf(14.dp, size * 0.3f))
                )
            }
        }
    }
}

@Composable
private fun ArtworkFallback(title: String, t: ImasTheme, size: Dp, hasColor: Boolean, icon: ImageVector) {
    if (hasColor) {
        Box(
            Modifier
                .fillMaxSize()
                .background(t.accent)
                .padding(size * 0.12f),
            contentAlignment = Alignment.Center
        ) {
            if (title.isNotEmpty()) {
                ImasFitText(
                    title,
                    style = ImasType.text(maxOf(9f, size.value * 0.13f).sp, FontWeight.Bold),
                    color = t.onAccent,
                    maxLines = 3,
                    minScale = 0.6f,
                    textAlign = TextAlign.Center
                )
            } else {
                Icon(icon, contentDescription = null, tint = t.onAccent.copy(alpha = 0.85f), modifier = Modifier.size(size * 0.4f))
            }
        }
    } else {
        Box(Modifier.fillMaxSize().background(DS.fill), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = DS.ink3, modifier = Modifier.size(maxOf(10.dp, size * 0.36f)))
        }
    }
}

// MARK: - 記号の札

/** 記号の大きさ (iOS `ImasIconTile.Size`)。外形の一辺。 */
enum class ImasIconTileSize(val frame: Dp, internal val glyph: Dp) {
    /** 統計タイル。 */
    S28(28.dp, 20.dp),

    /** 行の先頭 (設定・記録)。 */
    S32(32.dp, 22.dp),

    /** 予定の行。 */
    S36(36.dp, 24.dp),

    /** 入口カード。 */
    S44(44.dp, 28.dp),

    /** 空状態。 */
    S56(56.dp, 38.dp)
}

/** 記号の色 (iOS `ImasIconTile.Tone`)。 */
enum class ImasIconTileTone {
    /** 実体の色 (無ければ墨)。 */
    THEMED,

    /** 灰。 */
    NEUTRAL,

    /** 墨。 */
    SOLID,
    POSITIVE,
    ATTENTION,
    NEGATIVE
}

/**
 * 記号 1 つ (iOS `ImasIconTile`)。行の先頭・空状態・入口で同じ大きさにする。地は敷かない
 * (記号を淡い色の角丸四角に入れると、どのアプリにもある見た目になる)。**記号は減らさない** (目印として読まれている)。
 *
 * @param categoryKey 実体の色 hex を持たない分類 (record_type 等) で塗り分けたいときの分類キー。
 *   [seed]/[brand] の代わりに `ImasTheme.forCategoryKey` で導出する (iOS `derive(categoryKey:)` と同じ)。
 *   指定すると [seed]/[brand] は無視する。
 */
@Composable
fun ImasIconTile(
    icon: ImageVector,
    modifier: Modifier = Modifier,
    size: ImasIconTileSize = ImasIconTileSize.S32,
    tone: ImasIconTileTone = ImasIconTileTone.THEMED,
    seed: String? = null,
    brand: String? = null,
    categoryKey: String? = null
) {
    val t = if (categoryKey != null) {
        ImasTheme.forCategoryKey(categoryKey, LocalImasColors.current.dark)
    } else {
        ImasChipColors.theme(seed, brand, null)
    }
    val color = when (tone) {
        ImasIconTileTone.THEMED -> if (t.isNeutral) DS.ink else t.accent
        ImasIconTileTone.NEUTRAL -> DS.ink2
        ImasIconTileTone.SOLID -> DS.ink
        ImasIconTileTone.POSITIVE -> DS.successInk
        ImasIconTileTone.ATTENTION -> DS.warning
        ImasIconTileTone.NEGATIVE -> DS.danger
    }
    Box(modifier.size(size.frame).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(size.glyph))
    }
}

// MARK: - 色の丸

/** 色の丸の大きさ (iOS `ImasSwatch.Size`)。 */
enum class ImasSwatchSize(val diameter: Dp) {
    /** 名前の前の点。 */
    DOT(8.dp),

    /** 行・チップの中。 */
    SMALL(16.dp),

    /** 選ぶ・比べる。 */
    LARGE(28.dp)
}

/** 色の読み上げ名 (コアの `colorAccessibilityName`)。色の数は有界なので hex ごとに覚え、行ごとに FFI を呼ばない。 */
internal object ImasColorNames {
    private val cache = HashMap<String, String>()

    fun of(hex: String?): String = synchronized(cache) {
        cache.getOrPut(hex.orEmpty()) { colorAccessibilityName(hex) }
    }
}

/**
 * 色そのものを見せる丸 (iOS `ImasSwatch`。タグの色・ペンライトの色・イメージカラー)。
 * 色はデータの値なので hex をそのまま塗る (導出を通さない唯一の部品)。読み上げは色名。
 *
 * @param diameter 既定の 3 段階に無い寸法が要るとき (他画面の既存の大きさに揃える移行期など)。
 * @param isDecorative 名前が隣に書いてあり、色名を読み上げなくてよいとき。
 * @param isSelected 選んだ色の丸に墨の輪を付ける (色の格子から選ぶ画面)。
 */
@Composable
fun ImasSwatch(
    hex: String?,
    modifier: Modifier = Modifier,
    size: ImasSwatchSize = ImasSwatchSize.SMALL,
    diameter: Dp = size.diameter,
    isDecorative: Boolean = false,
    isSelected: Boolean = false
) {
    val showsRing = diameter > ImasSwatchSize.DOT.diameter
    val ringWidth = when {
        isSelected -> 2.5.dp
        showsRing -> 0.5.dp
        else -> 0.dp
    }
    val a11y = if (isDecorative) Modifier.clearAndSetSemantics { }
    else Modifier.clearAndSetSemantics { contentDescription = "カラー: ${ImasColorNames.of(hex)}" }
    Box(
        modifier
            .size(diameter)
            .background(hex?.let(::hexToColor) ?: Color.Gray, CircleShape)
            .then(if (ringWidth > 0.dp) Modifier.border(ringWidth, if (isSelected) DS.ink else DS.sep, CircleShape) else Modifier)
            .then(a11y)
    )
}

// MARK: - リードバー

/**
 * 一覧の行頭の控えめな実体色の帯 (iOS `ImasLeadBar`。ライブ・公演・曲のブランド)。
 *
 * 引数の名前は Android の今の呼び出しに合わせる (iOS の `seed` / `brand` が [seedHex] / [brandId])。
 *
 * @param height 帯の高さ。null なら親の高さいっぱい (親の高さが決まっていること)。
 * @param rainbow 合同ライブ等で虹色にする。
 */
@Composable
fun ImasLeadBar(
    seedHex: String? = null,
    brandId: String? = null,
    height: Dp? = 40.dp,
    rainbow: Boolean = false,
    modifier: Modifier = Modifier
) {
    val solid = imasThemeForBrand(seedHex, brandId).bar
    Box(
        modifier
            .width(DS.Size.leadBar)
            .then(if (height != null) Modifier.height(height) else Modifier.fillMaxHeight())
            .clip(RoundedCornerShape(DS.Size.leadBar / 2))
            // 虹色はくっきり区切った縞 (溶かさない)。
            .drawBehind { drawRect(if (rainbow) imasStripesVertical(ImasRainbow, size.height) else SolidColor(solid)) }
            .clearAndSetSemantics { }
    )
}

// MARK: - 歌唱者

/**
 * 歌唱者 1 人 (iOS `ImasPerformerChip`)。ペンライト + 名前。欠席は薄字 + 取り消し線。
 * セトリの行・予想の根拠・出演者の一覧で使う。名前は 1 人単位で折り返す。
 *
 * @param seed アイドルのイメージカラー hex。無ければ薄い墨の点。
 * @param secondary 名前の下にもう 1 行添える副の表記 (役名・別名義など。渡した画面だけで使う)。
 */
@Composable
fun ImasPerformerChip(
    name: String,
    modifier: Modifier = Modifier,
    seed: String? = null,
    isAbsent: Boolean = false,
    secondary: String? = null
) {
    val penlight = if (seed == null) DS.ink3 else imasThemeForBrand(seed, null).penlight
    Row(
        modifier.clearAndSetSemantics {
            contentDescription = listOfNotNull(name, secondary).joinToString("、") + if (isAbsent) " 欠席" else ""
        },
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasPenlight(
            color = penlight,
            size = ImasPenlightSize.SMALL,
            modifier = Modifier.alpha(if (isAbsent) 0.35f else 1f)
        )
        if (secondary != null) {
            Column {
                Text(
                    name,
                    style = ImasType.text(13.sp),
                    color = if (isAbsent) DS.ink3 else DS.ink2,
                    textDecoration = if (isAbsent) TextDecoration.LineThrough else null,
                    maxLines = 1,
                    softWrap = false
                )
                Text(
                    secondary,
                    style = ImasType.text(10.sp),
                    color = DS.ink3,
                    textDecoration = if (isAbsent) TextDecoration.LineThrough else null,
                    maxLines = 1,
                    softWrap = false
                )
            }
        } else {
            Text(
                name,
                style = ImasType.text(13.sp),
                color = if (isAbsent) DS.ink3 else DS.ink2,
                textDecoration = if (isAbsent) TextDecoration.LineThrough else null,
                maxLines = 1,
                softWrap = false
            )
        }
    }
}
