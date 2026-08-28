package com.fugaif.imaslivedb.ui.theme

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.fugaif.imaslivedb.di.AppModule

/**
 * アプリ全体の見え方を変える表示設定の保存先 (iOS `@AppStorage` に対応する 1 箇所)。
 *
 * ここが ViewModel ではなく object なのは、読み手が ViewModel を持てない位置に居るため:
 * 設定を最初に適用するのは合成のルート ([ImasLiveDBTheme]) で、そこは Activity が
 * `ImasLiveDBTheme { ... }` と呼ぶだけの場所であり、ViewModel も引数も差し込めない。
 * 値は Compose のスナップショット state で持つので、設定画面で書き換えれば
 * 参照している画面がその場で再コンポーズされる (iOS の `@AppStorage` と同じ体験)。
 *
 * 保存キーは **iOS の UserDefaults キーと同名**にしてある。バックアップの引き継ぎや
 * ドキュメント上で「同じ設定」だと分かるようにするため、Android 側で命名し直さない
 * ([com.fugaif.imaslivedb.data.notification.NotificationCategory] と同じ方針)。
 * 保存先ファイルは `SettingsViewModel` の `default_brand_id` と同じ "imas_settings"。
 */
object AppPreferences {

    private const val PREFS_NAME = "imas_settings"

    // iOS `MyPageView` の @AppStorage キーと 1:1。
    private const val KEY_TEXT_SCALE = "text_scale"
    private const val KEY_EVENT_NAME_ABBREVIATE = "event_name_abbreviate"
    private const val KEY_COLLECTION_INCLUDE_STREAM = "collection_include_stream"
    private const val KEY_THEME_USE_OSHI_COLOR = "theme_use_oshi_color"
    private const val KEY_THEME_OSHI_IDOL_ID = "theme_oshi_idol_id"
    private const val KEY_THEME_OSHI_COLOR = "theme_oshi_color"

    /**
     * 文字サイズの選択肢 (極小 / 小 / 中 / 大 / 特大)。iOS `MyPageView.textScaleOptions` と同値。
     * 中 (1.0) を境に縮小・拡大の両方向へ振れる。
     */
    val textScaleOptions = listOf(0.7f, 0.85f, 1.0f, 1.15f, 1.3f)
    val textScaleLabels = listOf("極小", "小", "中", "大", "特大")

    private var prefs: SharedPreferences? = null

    // 値は「private な可変 state + 公開の読み取り専用プロパティ + 明示的な変更関数」で持つ。
    // `var x by mutableStateOf(...) ; private set` にすると自動生成の setter (setX) が
    // 保存処理つきの `setX(...)` 関数と JVM シグネチャで衝突するため、この形にしている。
    // 読み取りは state 経由なので Compose の購読はそのまま効く。

    private var textScaleState by mutableFloatStateOf(1.0f)
    private var abbreviateState by mutableStateOf(true)
    private var includeStreamState by mutableStateOf(false)
    private var useOshiColorState by mutableStateOf(false)
    private var oshiIdolIdState by mutableStateOf("")
    private var oshiColorHexState by mutableStateOf("")

    /**
     * アプリ内の文字サイズ倍率。OS のフォントサイズ設定に**乗算**で重ねる追加倍率で、
     * OS 設定を置き換えるものではない (iOS が Dynamic Type に乗算するのと同じ)。
     */
    val textScale: Float get() = textScaleState

    /** ライブ名の作品名プレフィックスを一覧で省略するか。既定 ON (iOS と同じ)。 */
    val abbreviateEventNames: Boolean get() = abbreviateState

    /** 披露回収の判定に配信参加を含めるか。既定 OFF = 現地参加のみ。 */
    val includeStreamInCollection: Boolean get() = includeStreamState

    /** 担当 (推し) のイメージカラーをアプリ全体のアクセントに使うか。 */
    val useOshiColor: Boolean get() = useOshiColorState

    /** テーマに使う担当アイドル ID (複数担当のうち 1 人)。 */
    val oshiIdolId: String get() = oshiIdolIdState

    /** 解決済みのテーマ色 hex。空 = 無効 (既定アクセントにフォールバック)。 */
    val oshiColorHex: String get() = oshiColorHexState

    /**
     * SharedPreferences から現在値を読み込む。合成のルートと設定画面から呼ぶ (冪等)。
     *
     * 再バインドしても値を読み直すだけなので、プロセス内で何度呼んでも安全。
     */
    fun bind(context: Context) {
        val p = prefs ?: context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .also { prefs = it }

        textScaleState = p.getFloat(KEY_TEXT_SCALE, 1.0f)
        abbreviateState = p.getBoolean(KEY_EVENT_NAME_ABBREVIATE, true)
        includeStreamState = p.getBoolean(KEY_COLLECTION_INCLUDE_STREAM, false)
        useOshiColorState = p.getBoolean(KEY_THEME_USE_OSHI_COLOR, false)
        oshiIdolIdState = p.getString(KEY_THEME_OSHI_IDOL_ID, "").orEmpty()
        oshiColorHexState = p.getString(KEY_THEME_OSHI_COLOR, "").orEmpty()

        pushCollectionScope(context)
    }

    fun setTextScale(value: Float) {
        textScaleState = value
        prefs?.edit()?.putFloat(KEY_TEXT_SCALE, value)?.apply()
    }

    fun setAbbreviateEventNames(value: Boolean) {
        abbreviateState = value
        prefs?.edit()?.putBoolean(KEY_EVENT_NAME_ABBREVIATE, value)?.apply()
    }

    /**
     * 回収に配信参加を含めるかを切り替える。
     *
     * 保存するだけでは自動回収の集合は変わらない (判定は SQL の WHERE 句なので、
     * 次にクエリを引いたときの結果が変わる)。そのため即座にリポジトリへ押し込み、
     * 回収ダッシュボードや共有カードが次に引いた時点から新しい条件で数え直させる
     * (iOS の `UserMarkService.refreshAutoCollected()` に相当)。
     */
    fun setIncludeStreamInCollection(context: Context, value: Boolean) {
        includeStreamState = value
        prefs?.edit()?.putBoolean(KEY_COLLECTION_INCLUDE_STREAM, value)?.apply()
        pushCollectionScope(context)
    }

    fun setUseOshiColor(value: Boolean) {
        useOshiColorState = value
        prefs?.edit()?.putBoolean(KEY_THEME_USE_OSHI_COLOR, value)?.apply()
    }

    fun setOshiIdolId(value: String) {
        oshiIdolIdState = value
        prefs?.edit()?.putString(KEY_THEME_OSHI_IDOL_ID, value)?.apply()
    }

    fun setOshiColorHex(value: String) {
        oshiColorHexState = value
        prefs?.edit()?.putString(KEY_THEME_OSHI_COLOR, value)?.apply()
    }

    /**
     * ライブ名の表示整形。設定 OFF なら正式名称をそのまま返す。
     *
     * プレフィックス表そのものは既存の [com.fugaif.imaslivedb.ui.songs.eventDisplayName]
     * に任せる (同じ表を 2 箇所に置くと片方だけブランドが増えて食い違う)。
     * 本来はあちらが直接この設定を読むべきだが、今回の変更範囲では `ui/songs` を
     * 触らないため、設定を見る入口だけをここに置いて呼び分けている。
     *
     * 正式名称が要る箇所 (詳細タイトル・共有文・端末カレンダーへ登録する予定名) では使わない。
     */
    fun eventDisplayName(name: String): String =
        if (abbreviateEventNames) com.fugaif.imaslivedb.ui.songs.eventDisplayName(name) else name

    /** 回収の集計条件をリポジトリへ反映する。DB は開かないので合成中に呼んでも重くない。 */
    private fun pushCollectionScope(context: Context) {
        AppModule.from(context).userMarkRepository.includeStreamInCollection = includeStreamInCollection
    }
}
