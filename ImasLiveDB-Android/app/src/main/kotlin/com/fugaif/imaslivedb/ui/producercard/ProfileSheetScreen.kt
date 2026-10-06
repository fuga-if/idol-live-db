package com.fugaif.imaslivedb.ui.producercard

import android.graphics.Bitmap
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.producercard.ProfileSheetAssembler
import com.fugaif.imaslivedb.data.producercard.ProfileSheetMaterials
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.share.ProfileSheetPreview
import com.fugaif.imaslivedb.ui.share.ShareCardFiles
import com.fugaif.imaslivedb.ui.share.ShareCardSaveResult
import com.fugaif.imaslivedb.ui.share.rememberShareCardCapture
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import uniffi.imas_core.ProfileSheet
import uniffi.imas_core.profileSheetLayout
import uniffi.imas_core.profileSheetSizes
import uniffi.imas_core.profileSheetStyles

private const val FILE_PREFIX = "profile_sheet"

/**
 * プロフィール帳: P としての自己紹介を、履歴書・職務経歴書の様式の 1 枚絵にして SNS に貼る。
 * iOS `ProfileSheetView` の移植。
 *
 * 名前・写真・書体・リンク・自分の QR は P名刺のもの、担当・記録はアプリから。様式・大きさ・載せる記録は
 * 編集シート ([ProfileSheetEditorSheet]) で決め、端末の自分の名刺の行に持つ。
 * 欄の割り当て・行の組み立てはコア (`profileSheetLayout`)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileSheetScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val scope = rememberCoroutineScope()
    val capture = rememberShareCardCapture()

    var card by remember { mutableStateOf<MyProducerCard?>(null) }
    var materials by remember { mutableStateOf(ProfileSheetMaterials.EMPTY) }
    var loaded by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<MyProducerCard?>(null) }
    var exporting by remember { mutableStateOf(false) }
    var exportError by remember { mutableStateOf<String?>(null) }
    var saveError by remember { mutableStateOf<String?>(null) }
    // Android 9 以下の保存経路。保存先を選んで戻ってくるまで画像を持っておく。
    var pendingSave by remember { mutableStateOf<Bitmap?>(null) }

    suspend fun load() {
        val mine = module.producerCardRepository.myCard()
        // 材料を読み終えてから名刺を入れる (読み込み中に編集シートを空の材料で開かせない)。
        if (mine != null) materials = ProfileSheetAssembler.load(context, module, mine)
        card = mine
        loaded = true
    }
    LaunchedEffect(Unit) { load() }

    val styles = remember { profileSheetStyles() }
    val sizes = remember { profileSheetSizes() }

    /** 様式・大きさを選んだらその場で保存する (材料は変わらないので読み直さない)。 */
    fun saveSheet(sheet: ProfileSheet) {
        val current = card ?: return
        val updated = current.withProfile(sheet)
        card = updated
        scope.launch {
            runCatching {
                val latest = module.producerCardRepository.myCard() ?: current
                module.producerCardRepository.saveMyCard(latest.withProfile(sheet))
            }.onFailure { saveError = "もう一度試してください。" }
        }
    }

    val documentPicker = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("image/png")) { uri ->
        val bitmap = pendingSave
        pendingSave = null
        if (uri == null || bitmap == null) return@rememberLauncherForActivityResult
        scope.launch {
            val ok = ShareCardFiles.writeTo(context, uri, bitmap)
            Toast.makeText(context, if (ok) "画像を保存しました" else "保存に失敗しました", Toast.LENGTH_SHORT).show()
        }
    }

    /** 焼いた画像を渡す。焼けなければ知らせる。 */
    fun withImage(action: suspend (Bitmap) -> Unit) {
        exporting = true
        scope.launch {
            val bitmap = capture.toBitmap()
            if (bitmap == null) exportError = "もう一度試すか、アプリを再起動してください。" else action(bitmap)
            exporting = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("プロフィール帳") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                },
                actions = {
                    if (card != null) {
                        IconButton(onClick = { editing = card }) {
                            Icon(Icons.Filled.Edit, contentDescription = "載せる記録を選ぶ")
                        }
                    }
                }
            )
        }
    ) { padding ->
        ImasPage(modifier = Modifier.padding(padding)) {
            val mine = card
            when {
                !loaded -> ImasInlineLoading()
                mine != null -> Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                    val layout = profileSheetLayout(mine.profile, materials.record)
                    ProfileSheetPreview(
                        layout, materials, capture,
                        Modifier.semantics { contentDescription = "${layout.title}の見本" }
                    )
                    // 様式と大きさはここでも切り替え、選んだらその場で保存する。
                    val sheet = mine.profile
                    ImasSegmented(
                        labels = styles.map { it.label },
                        selection = styles.indexOfFirst { it.style == sheet.style },
                        onSelect = { i -> saveSheet(sheet.copy(style = styles[i].style)) }
                    )
                    ImasSegmented(
                        labels = sizes.map { it.label },
                        captions = sizes.map { it.caption },
                        selection = sizes.indexOfFirst { it.size == sheet.size },
                        onSelect = { i -> saveSheet(sheet.copy(size = sizes[i].size)) }
                    )
                    ImasButton(
                        title = "画像を書き出す", icon = Icons.Filled.Share, role = ImasButtonRole.PRIMARY,
                        size = ImasButtonSize.LARGE, fillsWidth = true, isLoading = exporting,
                        onClick = { withImage { ShareCardFiles.share(context, it, FILE_PREFIX) } }
                    )
                    ImasCardList {
                        ImasActionRow(
                            title = "写真に保存", icon = Icons.Filled.Download,
                            onClick = {
                                withImage { bitmap ->
                                    when (ShareCardFiles.saveToPictures(context, bitmap, FILE_PREFIX)) {
                                        ShareCardSaveResult.Saved ->
                                            Toast.makeText(context, "ピクチャに保存しました", Toast.LENGTH_SHORT).show()
                                        ShareCardSaveResult.NeedsDocumentPicker -> {
                                            pendingSave = bitmap
                                            documentPicker.launch(ShareCardFiles.fileName(FILE_PREFIX))
                                        }
                                        ShareCardSaveResult.Failed ->
                                            Toast.makeText(context, "保存に失敗しました", Toast.LENGTH_SHORT).show()
                                    }
                                }
                            }
                        )
                    }
                    ImasNote("載せる記録と担当ブランドの丸は右上の鉛筆から。名前・写真・書体・リンクは P名刺のものを使います。")
                }
            }
        }
    }

    editing?.let { editingCard ->
        ProfileSheetEditorSheet(
            card = editingCard,
            materials = materials,
            onSave = { sheet ->
                val saved = module.producerCardRepository.myCard() ?: editingCard
                module.producerCardRepository.saveMyCard(saved.withProfile(sheet))
                load()
            },
            onDismiss = { editing = null }
        )
    }
    ImasErrorAlert(message = saveError, onDismiss = { saveError = null }, title = "保存できませんでした")
    ImasErrorAlert(message = exportError, onDismiss = { exportError = null }, title = "画像を書き出せませんでした")
}
