package com.fugaif.imaslivedb.data.local

import android.content.Context
import android.content.SharedPreferences
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import uniffi.imas_core.BrandRoleBrand
import uniffi.imas_core.BrandRoleRecord
import uniffi.imas_core.BrandRoleRow
import uniffi.imas_core.BrandRoleSettings
import uniffi.imas_core.BrandRoleVisit
import uniffi.imas_core.brandRoleSettings
import uniffi.imas_core.brandRolesConfigured
import uniffi.imas_core.brandRolesToJson

/**
 * 担当ブランド (アプリ全体の設定)。iOS `BrandRoleStore` と対。ブランドごとに なし / 担当 / メイン の 3 段で、メインは複数可。
 *
 * 端末の設定 (SharedPreferences の `imas_settings`) に保存の形 (コアの `brandRolesToJson`) の文字列を 1 つ持ち、
 * バックアップ (`brandRoles`) で運ぶ。空は「まだ決めていない」で、そのときはコアが記録 (担当アイドル・参加した公演)
 * から既定を組む (`brandRoleSettings`)。段の扱い・既定の組み方・保存の形はすべてコア。ここは読み書きと材料集めだけ。
 */
object BrandRoleStore {
    /** iOS の UserDefaults と同じキー。 */
    const val KEY = "brand_roles_json"

    /** はじめの案内 (担当ブランドを選ぶシート) を出したか。スキップしても 1 度きり。 */
    const val PROMPTED_KEY = "brand_roles_prompted"
    private const val PREFS_NAME = "imas_settings"

    private val state = MutableStateFlow("")

    /** 今の保存の形 (変わると流れる。設定の画面・はじめの案内・バックアップの取り込み)。 */
    val json: StateFlow<String> get() = state.asStateFlow()

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun json(context: Context): String =
        prefs(context).getString(KEY, null).orEmpty().also { state.value = it }

    fun isConfigured(context: Context): Boolean = brandRolesConfigured(json(context))

    /** はじめの案内を出すか (まだ決めておらず、まだ出していない)。 */
    fun shouldPrompt(context: Context): Boolean =
        !isConfigured(context) && !prefs(context).getBoolean(PROMPTED_KEY, false)

    fun markPrompted(context: Context) {
        prefs(context).edit().putBoolean(PROMPTED_KEY, true).apply()
    }

    fun save(context: Context, rows: List<BrandRoleRow>) {
        write(context, brandRolesToJson(rows))
    }

    /** バックアップから戻す (保存の形のまま)。戻すかどうかはコアの `brandRolesJsonToRestore`。 */
    fun restore(context: Context, json: String) {
        if (!brandRolesConfigured(json)) return
        write(context, json)
    }

    private fun write(context: Context, json: String) {
        prefs(context).edit().putString(KEY, json).putBoolean(PROMPTED_KEY, true).apply()
        state.value = json
    }

    /** 既定を組む材料 (ブランド・担当アイドルのブランド・参加した公演のブランド)。 */
    suspend fun loadRecord(module: AppModule): BrandRoleRecord {
        val brands = runCatching { module.statsRepository.fetchBrands() }.getOrDefault(emptyList())
        val oshiIds = runCatching { module.userMarkRepository.pickedIdolIdList() }.getOrDefault(emptyList())
        val idols = if (oshiIds.isEmpty()) emptyList()
        else runCatching { module.idolRepository.fetchIdolsByIds(oshiIds) }.getOrDefault(emptyList())
        val idolById = idols.associateBy { it.id }
        val repo = module.producerCardRepository
        val refs = runCatching { repo.attendedShowRefs() }.getOrDefault(emptyList())
        val shows = runCatching { repo.showInfos(refs.map { it.showId }) }.getOrDefault(emptyMap())
        return BrandRoleRecord(
            today = JstDay.today(),
            brands = brands.map { BrandRoleBrand(it.id, it.shortName, it.color, it.sortOrder.toLong()) },
            oshiBrandIds = oshiIds.mapNotNull { idolById[it]?.brandId },
            visits = refs.map { BrandRoleVisit(it.date, shows[it.showId]?.brandId) }
        )
    }

    /** 今の設定 (まだ決めていなければ記録から組んだ既定)。 */
    suspend fun load(context: Context, module: AppModule): BrandRoleSettings =
        brandRoleSettings(json(context), loadRecord(module))
}

/**
 * 初回起動の担当ブランドの案内 (iOS はオンボーディングの後に続けて出す。Android は起動の案内が無いので入れた直後の起動で)。
 * 入れたばかり (更新ではない) の最初の起動で、まだ決めていない・まだ案内していないときだけ。1 度見たら起動では出さない。
 */
object BrandRoleLaunchPrompt {
    private const val PREFS_NAME = "imas_settings"
    private const val LAUNCHED_KEY = "brand_roles_launch_checked"

    /** 今回の起動で出すか (出すかどうかに関わらず、最初の起動の印を付ける)。 */
    fun consume(context: Context, openedByLink: Boolean): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(LAUNCHED_KEY, false)) return false
        prefs.edit().putBoolean(LAUNCHED_KEY, true).apply()
        val info = runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull() ?: return false
        val freshInstall = info.firstInstallTime == info.lastUpdateTime
        return freshInstall && !openedByLink && BrandRoleStore.shouldPrompt(context)
    }
}
