package com.fugaif.imaslivedb.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.ui.designsystem.ImasActionRow
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasProse
import com.fugaif.imaslivedb.ui.designsystem.ImasProseBlock
import com.fugaif.imaslivedb.ui.theme.DS
import uniffi.imas_core.cardNameFonts
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.runtime.remember

/**
 * プライバシーポリシー / 利用規約 / サポート / オープンソースライセンス。
 * iOS `Views/About` 配下の各 swift ファイルの移植 (オープンソースライセンスのみ Android 固有)。
 * `NavRoutes`/`AppNavigation` は他画面監査と競合するため触らず、`SettingsScreen` から
 * フルスクリーン `Dialog` として開く (`RecentEditsScreen.SetlistEditScreen` と同じパターン)。
 * 本文 (規約・プライバシーポリシー) は一字も変えず、見出し・箇条書きへの組み替えだけ行う。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InfoScreenScaffold(title: String, onBack: () -> Unit, content: @Composable () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                }
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            content()
        }
    }
}

private const val LAST_UPDATED = "最終更新日: 2026年4月23日"

@Composable
fun PrivacyPolicyScreen(onBack: () -> Unit) {
    InfoScreenScaffold(title = "プライバシーポリシー", onBack = onBack) {
        ImasPage {
            ImasProse(
                blocks = listOf(
                    ImasProseBlock.Heading("アプリの概要"),
                    ImasProseBlock.Paragraph(
                        "本アプリ（ImasLiveDB）は、アイドルマスターシリーズのライブ・セットリスト情報を管理・閲覧するための非公式ファンメイドアプリです。株式会社バンダイナムコエンターテインメントをはじめとする権利者とは一切関係ありません。"
                    ),
                    ImasProseBlock.Heading("収集するデータ"),
                    ImasProseBlock.Bullets(
                        listOf(
                            "端末識別子（UUID）: 端末内にのみ保存される匿名の識別子です。個人情報と紐付けることはありません。",
                            "アプリ設定: デフォルトブランドなどの設定は端末内のみに保存されます。",
                            "アカウント情報: コミュニティ機能を利用する場合、Google アカウントによるログインが必要です。投稿したセットリスト・修正提案などのコンテンツはサーバーに保存・公開されます。"
                        )
                    ),
                    ImasProseBlock.Heading("サードパーティサービス"),
                    ImasProseBlock.Bullets(
                        listOf(
                            "Cloudflare Workers: アプリの API 通信先として利用しています。",
                            "Spotify: 設定で連携した場合だけ、曲名と歌唱者名を検索語として Spotify に送り、あなたの Spotify アカウントにプレイリストを作ります。使う Client ID とログインの鍵は端末の中にだけ保存し、このアプリのサーバには送りません。",
                            "Google Sign-In: ログイン認証に利用しています。"
                        )
                    ),
                    ImasProseBlock.Heading("データの共有"),
                    ImasProseBlock.Paragraph(
                        "コミュニティ機能で投稿したコンテンツ（セットリスト報告・修正提案など）は他のユーザーに公開されます。投稿内容に個人情報を含めないようご注意ください。"
                    ),
                    ImasProseBlock.Heading("ユーザーの権利"),
                    ImasProseBlock.Paragraph(
                        "アカウントおよび投稿データの削除は、設定画面の「アカウントを削除」からいつでも行えます。個別のお問い合わせは GitHub Issue にてご連絡ください。"
                    ),
                    ImasProseBlock.Heading("連絡先"),
                    ImasProseBlock.Paragraph(
                        "プライバシーに関するお問い合わせ・データ削除依頼は下記 GitHub Issue からお願いします。\nhttps://github.com/fuga-if/imas-live-privacy/issues/new"
                    ),
                    ImasProseBlock.Note(LAST_UPDATED)
                )
            )
        }
    }
}

@Composable
fun TermsOfServiceScreen(onBack: () -> Unit) {
    InfoScreenScaffold(title = "利用規約", onBack = onBack) {
        ImasPage {
            ImasProse(
                blocks = listOf(
                    ImasProseBlock.Heading("免責・権利表記"),
                    ImasProseBlock.Paragraph(
                        "本アプリは非公式のファン制作アプリです。株式会社バンダイナムコエンターテインメント、株式会社バンダイナムコミュージックライブ、その他アイドルマスターシリーズに関わる権利者とは一切関係ありません。"
                    ),
                    ImasProseBlock.Heading("知的財産権"),
                    ImasProseBlock.Paragraph(
                        "アイドルマスターシリーズおよび関連するキャラクター・楽曲・ロゴ・イラスト等の著作権・商標権はすべて各権利者に帰属します。本アプリはこれらを無断で使用・複製・配布しません。"
                    ),
                    ImasProseBlock.Heading("使用している素材について"),
                    ImasProseBlock.Bullets(
                        listOf(
                            "ジャケット画像: 公式配信ストアの正式 API 経由で取得したもののみを表示しています。",
                            "歌詞: 使用していません。",
                            "キャラクターイラスト: 使用していません。",
                            "公式ロゴ: 使用していません。"
                        )
                    ),
                    ImasProseBlock.Heading("ユーザー投稿コンテンツ"),
                    ImasProseBlock.Paragraph(
                        "コミュニティ機能への投稿（セットリスト情報・修正提案など）は、ユーザー自身の責任において行ってください。投稿コンテンツに起因する問題について、開発者は責任を負いません。"
                    ),
                    ImasProseBlock.Heading("投稿コンテンツのライセンス"),
                    ImasProseBlock.Paragraph(
                        "ユーザーが投稿したコンテンツはサーバーに保存され、本アプリを利用する他のユーザーに公開されます。投稿することで、当該コンテンツをアプリ内で表示・利用することに同意したものとみなします。"
                    ),
                    ImasProseBlock.Heading("禁止事項"),
                    ImasProseBlock.Paragraph("以下の行為を禁止します。"),
                    ImasProseBlock.Bullets(
                        listOf(
                            "他者の著作権・商標権・プライバシーを侵害するコンテンツの投稿",
                            "他のユーザーへの嫌がらせ・誹謗中傷",
                            "スパムや虚偽情報の投稿",
                            "本アプリのシステムへの不正アクセス・改ざん"
                        )
                    ),
                    ImasProseBlock.Heading("サービスの変更・停止"),
                    ImasProseBlock.Paragraph(
                        "開発者は予告なくアプリの機能変更・サービス停止を行う場合があります。これによって生じた損害について開発者は責任を負いません。"
                    ),
                    ImasProseBlock.Heading("連絡先"),
                    ImasProseBlock.Paragraph(
                        "ご意見・不具合報告は GitHub Issue にてご連絡ください。\nhttps://github.com/fuga-if/imas-live-privacy/issues/new"
                    ),
                    ImasProseBlock.Note(LAST_UPDATED)
                )
            )
        }
    }
}

@Composable
fun SupportScreen(onBack: () -> Unit, onOpenGithubIssue: () -> Unit) {
    InfoScreenScaffold(title = "サポート", onBack = onBack) {
        ImasFormBackdrop(modifier = Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                ImasListSection("フィードバック・バグ報告") {
                    ImasActionRow(
                        title = "GitHub Issue で報告する",
                        onClick = onOpenGithubIssue,
                        icon = Icons.AutoMirrored.Filled.OpenInNew
                    )
                }
                ImasListSection("よくある質問") {
                    ImasProse(
                        blocks = SUPPORT_FAQS.flatMap { (q, a) ->
                            listOf(ImasProseBlock.Heading("Q. $q"), ImasProseBlock.Paragraph("A. $a"))
                        },
                        modifier = Modifier.padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV)
                    )
                }
            }
        }
    }
}

private val SUPPORT_FAQS = listOf(
    "データが古い・間違っている" to "GitHub Issue または コミュニティ機能の「修正提案」からご報告ください。確認後に反映します。",
    "ジャケット画像が表示されない" to "配信ストアのデータベースに登録されていない楽曲は画像が表示されません。",
    "同期に失敗する" to "通信環境をご確認のうえ、設定画面から「全データ同期」をお試しください。",
    "アプリが公式アプリではないのですか?" to "はい、本アプリは非公式のファンメイドアプリです。バンダイナムコエンターテインメント等とは一切関係ありません。"
)

/**
 * オープンソースライセンス一覧 (iOS `MyPageView` の OSS ライセンス節に対応)。
 *
 * 収録の基準は「アプリの配布物に実際に入るもの」= `app/build.gradle.kts` の
 * `implementation` 依存。ビルドやテストにしか使わない依存 (`debugImplementation` /
 * `testImplementation`) は配布されないので載せない。
 * 依存を足したらここも足すこと — 生成ツールを入れていないので同期は手動。
 */
@Composable
fun OssLicensesScreen(onBack: () -> Unit) {
    InfoScreenScaffold(title = "オープンソースライセンス", onBack = onBack) {
        ImasFormBackdrop(modifier = Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                ImasNote(
                    "本アプリは以下のオープンソースソフトウェアを利用しています。各ライセンスの全文は" +
                        "それぞれのプロジェクトの配布物に含まれます。",
                    modifier = Modifier.padding(horizontal = DS.Space.screen, vertical = DS.Space.gap)
                )
                ImasListSection {
                    OSS_LICENSES.forEach { (name, owner, license) ->
                        ImasNavRow(
                            title = name,
                            subtitle = "$owner ・ $license",
                            showsChevron = false,
                            titleLineLimit = Int.MAX_VALUE,
                            subtitleLineLimit = Int.MAX_VALUE
                        )
                    }
                    // P名刺の名前の書体 (同梱。一覧はコア)。押すと配布元を開く。
                    val uriHandler = LocalUriHandler.current
                    remember { cardNameFonts() }.forEach { font ->
                        ImasNavRow(
                            title = "${font.familyName} (P名刺の書体)",
                            subtitle = font.license,
                            titleLineLimit = Int.MAX_VALUE,
                            subtitleLineLimit = Int.MAX_VALUE,
                            onClick = { runCatching { uriHandler.openUri(font.sourceUrl) } }
                        )
                    }
                }
            }
        }
    }
}

private const val APACHE_2 = "Apache License 2.0"

private val OSS_LICENSES = listOf(
    Triple("AndroidX (Core / Lifecycle / Activity / Navigation / Security / Credentials)", "Google", APACHE_2),
    Triple("Jetpack Compose (UI / Material 3 / Material Icons)", "Google", APACHE_2),
    Triple("Room", "Google", APACHE_2),
    Triple("Glance (App Widget)", "Google", APACHE_2),
    Triple("Media3 / ExoPlayer", "Google", APACHE_2),
    Triple("Google Identity Services (googleid)", "Google", APACHE_2),
    Triple("Coil", "Coil Contributors", APACHE_2),
    Triple("OkHttp", "Square, Inc.", APACHE_2),
    Triple("Kotlin / kotlinx.coroutines", "JetBrains", APACHE_2),
    // JNA だけライセンスが違う。UniFFI が生成するバインディングが要求する実行時依存。
    Triple("JNA (Java Native Access)", "JNA Contributors", "Apache License 2.0 / LGPL 2.1 のデュアルライセンス"),
    Triple("imas-core", "本アプリの一部 (Rust)", "iOS 版と共有する自作のコアライブラリです。外部ライセンスはありません。")
)
