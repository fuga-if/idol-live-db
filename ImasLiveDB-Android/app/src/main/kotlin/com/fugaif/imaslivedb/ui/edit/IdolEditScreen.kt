package com.fugaif.imaslivedb.ui.edit

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.data.edit.putClearable
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.launch
import uniffi.imas_core.themeNormalizedHex

/**
 * アイドル編集。iOS `IdolEditView` の移植で、主に名前・読み・誕生日・色・属性の誤字修正用。
 *
 * **新規作成は無い**。サーバの `NO_CREATE_TYPES` に Idol が入っており、一般ユーザーの
 * `op=create` は `/edits` でも `/edit-requests` でも 400 になる (imas-live-api/src/ck_schema.ts)。
 * iOS も update 専用なので、ここも同じく既存アイドルの修正だけを扱う。
 */
@Composable
fun IdolEditScreen(
    original: Idol,
    onDismiss: () -> Unit,
    /**
     * 反映済みの Idol を返す (admin の即時反映時のみ)。呼び出し側が画面をその場で
     * 描き直せるようにするため、確定 ID ではなくレコードごと渡す
     * (IdolDetailViewModel には外から呼べる再読込の口が無い)。
     */
    onSaved: (Idol) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val key = original.id

    var name by rememberSaveable(key) { mutableStateOf(original.name) }
    var nameKana by rememberSaveable(key) { mutableStateOf(original.nameKana ?: "") }
    var nameRomaji by rememberSaveable(key) { mutableStateOf(original.nameRomaji ?: "") }
    var aliases by rememberSaveable(key) { mutableStateOf(original.aliases ?: "") }
    var brandId by rememberSaveable(key) { mutableStateOf(original.brandId) }
    var attribute by rememberSaveable(key) { mutableStateOf(original.attribute ?: "") }
    var sortOrder by rememberSaveable(key) { mutableIntStateOf(original.sortOrder) }
    var color by rememberSaveable(key) { mutableStateOf(original.color ?: "") }
    var birthday by rememberSaveable(key) { mutableStateOf(original.birthday ?: "") }
    var bloodType by rememberSaveable(key) { mutableStateOf(original.bloodType ?: "") }
    var birthPlace by rememberSaveable(key) { mutableStateOf(original.birthPlace ?: "") }
    var debutDate by rememberSaveable(key) { mutableStateOf(original.debutDate ?: "") }

    var brands by remember { mutableStateOf<List<Brand>>(emptyList()) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var requestedIssueUrl by remember { mutableStateOf<String?>(null) }
    var requestSent by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        brands = runCatching { AppModule.from(context).statsRepository.fetchBrands() }.getOrDefault(emptyList())
    }
    // Idol.brandId は非 null 列なので「未指定」は出さない (iOS の Picker も全ブランドのみ)。
    val brandOptions = remember(brands) { brands.map { it.id to it.name } }

    /**
     * マスタの色は `#RRGGBB` 表記で統一されており、サーバ validator (HEX_RE) もそれを正とする。
     * `#` を省いたり 3 桁短縮で打っても弾かれないよう、送る前にコアの正規化を通して補う
     * (iOS `IdolEditView.canonicalColor` と同じ)。正規化できない入力はそのまま送って
     * サーバに判定させる。
     */
    fun canonicalColor(): String {
        if (color.isEmpty()) return color
        val hex = themeNormalizedHex(color) ?: return color
        return "#" + hex.uppercase()
    }

    /**
     * 送信値から確定 Idol を組む。フォームに無い列 (身長/スリーサイズ/CV 等) は copy で
     * 丸ごと引き継ぐ。Room の upsert は行ごと REPLACE なので、ここを落とすとプロフィールが消える。
     */
    fun buildSaved(resolvedId: String, canonical: String): Idol = original.copy(
        id = resolvedId,
        name = name.trim(),
        nameKana = nameKana.nonEmptyTrimmed(),
        nameRomaji = nameRomaji.nonEmptyTrimmed(),
        brandId = brandId,
        color = canonical.nonEmptyTrimmed(),
        sortOrder = sortOrder,
        birthday = birthday.nonEmptyTrimmed(),
        bloodType = bloodType.nonEmptyTrimmed(),
        birthPlace = birthPlace.nonEmptyTrimmed(),
        attribute = attribute.nonEmptyTrimmed(),
        aliases = aliases.nonEmptyTrimmed(),
        debutDate = debutDate.nonEmptyTrimmed()
    )

    fun save() {
        val canonical = canonicalColor()
        val fields = mutableMapOf<String, Any?>(
            "name" to name.trim(),
            "brandId" to brandId,
            "sortOrder" to sortOrder
        )
        // update はサーバ側マージ (未送信 = 現状維持 / null 明示 = クリア)。
        fields.putClearable("nameKana", nameKana, original.nameKana)
        fields.putClearable("nameRomaji", nameRomaji, original.nameRomaji)
        fields.putClearable("color", canonical, original.color)
        fields.putClearable("birthday", birthday, original.birthday)
        fields.putClearable("bloodType", bloodType, original.bloodType)
        fields.putClearable("birthPlace", birthPlace, original.birthPlace)
        fields.putClearable("attribute", attribute, original.attribute)
        fields.putClearable("aliases", aliases, original.aliases)
        fields.putClearable("debutDate", debutDate, original.debutDate)

        val op = EditApi.EditOperation(
            op = EditApi.EditOp.UPDATE,
            recordType = "Idol",
            recordName = original.id,
            fields = fields
        )

        isSaving = true
        scope.launch {
            val result = submitMasterEdit(
                context = context,
                ops = listOf(op),
                summary = "アイドル編集",
                fallbackRecordName = original.id
            ) { resolvedId ->
                AppModule.from(context).database.syncDao().upsertIdols(listOf(buildSaved(resolvedId, canonical)))
            }
            isSaving = false
            when (result) {
                is MasterEditSubmitResult.Applied -> onSaved(buildSaved(result.recordName, canonical))
                is MasterEditSubmitResult.Requested -> {
                    requestedIssueUrl = result.issueUrl
                    requestSent = true
                }
                is MasterEditSubmitResult.Failed -> errorMessage = result.message
            }
        }
    }

    MasterEditScaffold(
        title = "アイドル編集",
        // iOS の保存ボタンは isSaving 以外で無効化しない。ここだけ厳しくすると
        // 「iOS では保存できるのに Android では保存できない」ズレになるので揃える。
        canSave = true,
        isSaving = isSaving,
        onCancel = onDismiss,
        onSave = ::save
    ) {
        EditSection("名前") {
            EditReadonlyRow("ID", original.id)
            EditTextField("名前", name, { name = it })
            EditTextField("カナ", nameKana, { nameKana = it })
            EditTextField("ローマ字", nameRomaji, { nameRomaji = it })
            EditTextField("別名 (カンマ区切り)", aliases, { aliases = it })
        }
        EditSection("分類") {
            EditDropdownField("ブランド", brandOptions, brandId) { brandId = it }
            EditTextField("属性 (cute/cool/passion 等)", attribute, { attribute = it })
            EditStepperRow("並び順", sortOrder, 0..9999) { sortOrder = it }
        }
        EditSection("プロフィール", footer = "カラーは #RRGGBB。# を省いても保存時に補います。") {
            EditTextField("カラー (#hex)", color, { color = it })
            EditTextField("誕生日 (MM-DD)", birthday, { birthday = it })
            EditTextField("血液型", bloodType, { bloodType = it })
            EditTextField("出身地", birthPlace, { birthPlace = it })
            EditTextField("実装日 (YYYY-MM-DD)", debutDate, { debutDate = it })
        }
    }

    errorMessage?.let { EditErrorDialog(it) { errorMessage = null } }

    if (requestSent) {
        EditRequestSentDialog(requestedIssueUrl) { requestSent = false; onDismiss() }
    }
}
