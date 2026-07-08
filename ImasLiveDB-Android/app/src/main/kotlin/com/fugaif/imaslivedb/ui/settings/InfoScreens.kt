package com.fugaif.imaslivedb.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * プライバシーポリシー / 利用規約 / サポート。iOS `Views/About` 配下の各 swift ファイルの移植。
 * `NavRoutes`/`AppNavigation` は他画面監査と競合するため触らず、`SettingsScreen` から
 * フルスクリーン `Dialog` として開く (`RecentEditsScreen.SetlistEditScreen` と同じパターン)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InfoScreenScaffold(title: String, onBack: () -> Unit, content: @Composable () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            content()
        }
    }
}

@Composable
private fun InfoSection(title: String, content: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
        Text(content, fontSize = 15.sp, color = DS.ink2)
    }
}

@Composable
private fun LastUpdated() {
    Text("最終更新日: 2026年4月23日", fontSize = 12.sp, color = DS.ink3)
}

@Composable
fun PrivacyPolicyScreen(onBack: () -> Unit) {
    InfoScreenScaffold(title = "プライバシーポリシー", onBack = onBack) {
        InfoSection(
            "アプリの概要",
            "本アプリ（ImasLiveDB）は、アイドルマスターシリーズのライブ・セットリスト情報を管理・閲覧するための非公式ファンメイドアプリです。株式会社バンダイナムコエンターテインメントをはじめとする権利者とは一切関係ありません。"
        )
        InfoSection(
            "収集するデータ",
            "・端末識別子（UUID）: 端末内にのみ保存される匿名の識別子です。個人情報と紐付けることはありません。\n" +
                "・アプリ設定: デフォルトブランドなどの設定は端末内のみに保存されます。\n" +
                "・アカウント情報: コミュニティ機能を利用する場合、Google アカウントによるログインが必要です。投稿したセットリスト・修正提案などのコンテンツはサーバーに保存・公開されます。"
        )
        InfoSection(
            "サードパーティサービス",
            "・Cloudflare Workers: アプリの API 通信先として利用しています。\n" +
                "・Google Sign-In: ログイン認証に利用しています。"
        )
        InfoSection(
            "データの共有",
            "コミュニティ機能で投稿したコンテンツ（セットリスト報告・修正提案など）は他のユーザーに公開されます。投稿内容に個人情報を含めないようご注意ください。"
        )
        InfoSection(
            "ユーザーの権利",
            "アカウントおよび投稿データの削除は、設定画面の「アカウントを削除」からいつでも行えます。個別のお問い合わせは GitHub Issue にてご連絡ください。"
        )
        InfoSection(
            "連絡先",
            "プライバシーに関するお問い合わせ・データ削除依頼は下記 GitHub Issue からお願いします。\nhttps://github.com/fuga-if/imas-live-privacy/issues/new"
        )
        LastUpdated()
    }
}

@Composable
fun TermsOfServiceScreen(onBack: () -> Unit) {
    InfoScreenScaffold(title = "利用規約", onBack = onBack) {
        InfoSection(
            "免責・権利表記",
            "本アプリは非公式のファン制作アプリです。株式会社バンダイナムコエンターテインメント、株式会社バンダイナムコミュージックライブ、その他アイドルマスターシリーズに関わる権利者とは一切関係ありません。"
        )
        InfoSection(
            "知的財産権",
            "アイドルマスターシリーズおよび関連するキャラクター・楽曲・ロゴ・イラスト等の著作権・商標権はすべて各権利者に帰属します。本アプリはこれらを無断で使用・複製・配布しません。"
        )
        InfoSection(
            "使用している素材について",
            "・ジャケット画像: 公式配信ストアの正式 API 経由で取得したもののみを表示しています。\n" +
                "・歌詞: 使用していません。\n" +
                "・キャラクターイラスト: 使用していません。\n" +
                "・公式ロゴ: 使用していません。"
        )
        InfoSection(
            "ユーザー投稿コンテンツ",
            "コミュニティ機能への投稿（セットリスト情報・修正提案など）は、ユーザー自身の責任において行ってください。投稿コンテンツに起因する問題について、開発者は責任を負いません。"
        )
        InfoSection(
            "投稿コンテンツのライセンス",
            "ユーザーが投稿したコンテンツはサーバーに保存され、本アプリを利用する他のユーザーに公開されます。投稿することで、当該コンテンツをアプリ内で表示・利用することに同意したものとみなします。"
        )
        InfoSection(
            "禁止事項",
            "以下の行為を禁止します。\n" +
                "・他者の著作権・商標権・プライバシーを侵害するコンテンツの投稿\n" +
                "・他のユーザーへの嫌がらせ・誹謗中傷\n" +
                "・スパムや虚偽情報の投稿\n" +
                "・本アプリのシステムへの不正アクセス・改ざん"
        )
        InfoSection(
            "サービスの変更・停止",
            "開発者は予告なくアプリの機能変更・サービス停止を行う場合があります。これによって生じた損害について開発者は責任を負いません。"
        )
        InfoSection(
            "連絡先",
            "ご意見・不具合報告は GitHub Issue にてご連絡ください。\nhttps://github.com/fuga-if/imas-live-privacy/issues/new"
        )
        LastUpdated()
    }
}

@Composable
fun SupportScreen(onBack: () -> Unit, onOpenGithubIssue: () -> Unit) {
    InfoScreenScaffold(title = "サポート", onBack = onBack) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("フィードバック・バグ報告", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            Row(
                modifier = Modifier.clickable(onClick = onOpenGithubIssue),
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, tint = Color(0xFF4A90D9))
                Text("GitHub Issue で報告する", fontSize = 15.sp, color = Color(0xFF4A90D9))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("よくある質問", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            FaqItem("データが古い・間違っている", "GitHub Issue または コミュニティ機能の「修正提案」からご報告ください。確認後に反映します。")
            FaqItem("ジャケット画像が表示されない", "配信ストアのデータベースに登録されていない楽曲は画像が表示されません。")
            FaqItem("同期に失敗する", "通信環境をご確認のうえ、設定画面から「全データ同期」をお試しください。")
            FaqItem("アプリが公式アプリではないのですか?", "はい、本アプリは非公式のファンメイドアプリです。バンダイナムコエンターテインメント等とは一切関係ありません。")
        }
    }
}

@Composable
private fun FaqItem(question: String, answer: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("Q. $question", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
        Text("A. $answer", fontSize = 15.sp, color = DS.ink2)
    }
}
