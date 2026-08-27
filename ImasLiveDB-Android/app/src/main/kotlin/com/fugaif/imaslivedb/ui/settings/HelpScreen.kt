package com.fugaif.imaslivedb.ui.settings

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

/**
 * ヘルプ (使い方カタログ)。iOS `Views/Help/HelpView.swift` の移植。
 *
 * 文面は iOS の `HelpCatalog.sections` から**機械的に変換**したもので、書き起こしていない。
 * 両 OS で説明が食い違うと「アプリによって出来ることが違う」と読めてしまうため、
 * 文言を片方だけ直さないこと (直すときは両方)。
 *
 * **ただし、実際に出来ることが違う項目はこちらの実装に合わせて書き換える。**
 * 機械変換した初版は「Apple Music に契約していればフル再生 OK」「Sign in with Apple」
 * 「マイページ → 画像インポート」のように、Android に無い機能や違う場所を案内していた。
 * 揃えるべきは文言ではなく「読んだ人が実際にたどり着けること」。
 *
 * アイコンだけは SF Symbol → Material Icons の対応を人が決めている。
 * 色 (tint) は iOS と同じ hex を渡し、`ImasTheme.derive` で両 OS 同じトークンに導出する。
 */
data class HelpSection(
    val icon: ImageVector,
    /** カテゴリ識別用の装飾テーマ seed (hex)。iOS と同じ値。 */
    val tint: String,
    val title: String,
    val summary: String,
    val body: List<HelpItem>
)

data class HelpItem(val label: String, val detail: String)

object HelpCatalog {
    val sections: List<HelpSection> = listOf(
    HelpSection(
        icon = Icons.Filled.Mic,
        tint = "#FF2D55",
        title = "ライブを探す",
        summary = "全ブランドのライブ・公演・セットリストを年別に閲覧できます。",
        body = listOf(
            HelpItem("年別リストで時系列に追える", "1000公演以上を年で分けて表示。新しい順なので、最新のライブから過去まで一気に俯瞰できます。"),
            HelpItem("ブランドでフィルタ", "右上の絞り込みボタンから、765AS / シンデレラ / ミリオン / SideM / シャニ / 学マス / ヴイアラ など特定ブランドだけに絞れます。"),
            HelpItem("種別 (live / stream / event / other) で絞れる", "本ライブ・配信・イベント・その他を切り替え可能。配信中心の活動だけ追いたい時に便利。"),
            HelpItem("詳細でセトリ・出演者・チケット情報を確認", "ライブをタップすると、公演日ごとのセトリ、出演アイドル、コーレス、参考動画、チケット情報まで確認できます。"),
            HelpItem("参加したライブを記録", "詳細画面から「参加した」をオンにすると、マイページの参加カウントに加算されます。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.QueueMusic,
        tint = "#5856D6",
        title = "楽曲を探す",
        summary = "2300曲以上を曲名・アルバム・シリーズで探索できます。",
        body = listOf(
            HelpItem("3 つの表示モード", "曲一覧 / アルバムグリッド / シリーズグリッド を絞り込みパネルから切り替え可能。"),
            HelpItem("試聴とジャケ写", "配信のある曲は 30 秒のプレビューを再生できます。ジャケ写も自動取得。"),
            HelpItem("歌唱履歴で深掘り", "曲詳細から「どのライブで何回歌われたか」を一覧表示。担当曲の披露頻度がわかります。"),
            HelpItem("オリジナルメンバーを表示", "曲のアイコン群はオリジナル歌唱メンバー (ライブ歌唱者ではなく)。ユニット曲はユニット名で表示されます。"),
            HelpItem("回収済 / 未回収で絞り込み", "マイマークで「回収済」を付けた曲だけ、または未回収だけを表示できます。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.Groups,
        tint = "#FF9500",
        title = "アイドル・CVを探す",
        summary = "全ブランドのアイドルを名前・CV名・属性で横断検索できます。",
        body = listOf(
            HelpItem("リスト / グリッド 切り替え", "上部の切り替えボタンで、密な一覧 (リスト) と画像中心のグリッドを切り替えられます。"),
            HelpItem("アイドル名 ↔ CV 名 で表示切替", "絞り込みパネルから「CV名で表示」に切り替えると、 声優名で一覧化されます。"),
            HelpItem("属性で絞り込み", "キュート/クール/パッション (CG)、 Fairy/Angel/Princess (ML)、 1年/3年 (学マス) などブランドごとの属性で絞れます。"),
            HelpItem("アイドル詳細で担当曲・出演ライブを確認", "アイドルをタップすると、担当曲リスト・出演ライブ・誕生日・カラーが見られます。"),
            HelpItem("別名 (aliases) も検索対象", "ロコ ↔ 伴田路子 のような別名表記も内部で同一アイドルとして紐づいています。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.Bookmark,
        tint = "#FF3B30",
        title = "マイマーク（記録）",
        summary = "担当アイドル・回収済楽曲・参加ライブを記録できます。",
        body = listOf(
            HelpItem("担当アイドル", "アイドル詳細から「担当」を付けると、マイページに集約されて確認できます。"),
            HelpItem("回収済 (持ってる) 楽曲", "曲詳細から「回収済」を付けると、自分のコレクション管理ができます。楽曲一覧で「回収済のみ」表示も可能。"),
            HelpItem("参加ライブ", "ライブ詳細から「参加した」を付けると、マイページに参加履歴が積み上がります。"),
            HelpItem("マイマークは端末に保存", "ローカル保存されるので、ログインなしで使えます。機種変更のときは 設定 → バックアップ の引き継ぎコードで移せます。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.Edit,
        tint = "#007AFF",
        title = "みんなで編集",
        summary = "ログインすればセトリ・楽曲・ライブ情報を直接編集でき、その場で全員に反映されます。",
        body = listOf(
            HelpItem("直接編集して、すぐ反映", "承認待ちはありません。ログインユーザーがセトリ・新曲・新イベント・コーレス・参考動画などを直接追加・修正でき、CloudKit 経由ですぐ全員の端末に届きます。Wikipedia のような共同編集スタイルです。"),
            HelpItem("編集には Google ログイン", "閲覧はログイン不要。編集に参加したい時だけ設定からログインしてください。各画面の「+」や鉛筆アイコンから編集できます。"),
            HelpItem("すべての編集に履歴が残る", "誰がいつ何を変えたかが変更前後つきで記録されます。各データの編集履歴や、プロデュースタブの「最近の編集」フィードからたどれます。"),
            HelpItem("「良かった」で感謝を伝える", "他の人の編集に「良かった」を付けられます。人気・感謝の指標で、付けた数・もらった数がマイページに表示されます。"),
            HelpItem("間違いはすぐ戻せる", "自分の編集はいつでも取り消せます。誤りや荒らしはワンタップで元に戻され、悪質な場合はアカウントが利用停止になります。安心して編集してください。"),
            HelpItem("貢献が積み上がる", "編集した数と「良かった」をもらった数で貢献度が積み上がり、マイページに称号バッジとして表示されます。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.Sell,
        tint = "#30B0C7",
        title = "タグ",
        summary = "ユーザー投稿のタグで曲を自由に分類できます。",
        body = listOf(
            HelpItem("曲にタグを付ける", "曲詳細から既存のタグを付けたり、新しいタグを作って付けたりできます。"),
            HelpItem("タグから曲を辿る", "タグ一覧 → タグ詳細から、そのタグが付いた曲を一覧表示。「夏曲」「バラード」「神曲」など好きな切り口で検索可能。"),
            HelpItem("タグの説明文を編集", "誰でもタグの説明を書き加えられます。Wikipedia のような共同編集スタイル。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.Palette,
        tint = "#AF52DE",
        title = "ペンライト投票",
        summary = "曲ごとの「振る色」をみんなで投票して可視化。",
        body = listOf(
            HelpItem("曲詳細から好きな色セットを投票", "公式パレットの中から、その曲で振りたい色 (単色 / 複数色) を選んで投票できます。"),
            HelpItem("集計結果を確認", "投票結果は色セット別の票数で表示。ライブ前の「色合わせ」用にどうぞ。"),
            HelpItem("1 端末 1 票で差し替え可能", "同じ曲に複数回投票しても、最新の選択で上書きされます (端末単位)。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.Headphones,
        tint = "#FF2D55",
        title = "イントロドン",
        summary = "曲のイントロを聴いて曲名を当てるクイズ。",
        body = listOf(
            HelpItem("配信のある曲で遊べる", "出題は 30 秒のプレビュー再生です。配信のある曲だけが出題対象になります。"),
            HelpItem("ブランド・難易度を選択", "ブランド絞り込みや、再生秒数で難易度調整できます。"),
            HelpItem("4 択で回答", "曲名の 4 択から選びます。パーティ対戦なら 1 台を 2 人で分けて早押しできます。"),
            HelpItem("ベストスコアを記録", "ブランドごとに自己ベストが残ります。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.Search,
        tint = "#8E8E93",
        title = "検索",
        summary = "「このタブを絞り込む」検索と、「全体を横断する」検索の 2 種類があります。",
        body = listOf(
            HelpItem("タブ内検索 = この一覧を絞り込む", "ライブ / 楽曲 / アイドル 各タブの検索バーは、いま表示中の一覧 (適用中の絞り込みも含む) をその場で絞り込みます。"),
            HelpItem("全体検索 = 横断して探す", "右上の虫眼鏡から、楽曲・アイドル・ライブをまとめて横断検索できます。タブをまたいで一気に目的の項目へ飛べます。"),
            HelpItem("見つからなければ全体検索へ", "タブ内検索で結果が無いときは「全体から検索」ボタンが出ます。同じ語句のまま 1 タップで横断検索に切り替えられます。"),
            HelpItem("アイドル別名にも対応", "「ロコ」と検索しても「伴田路子」がヒット。シャニやミリの別名表記も内部で名寄せ済み。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.CalendarMonth,
        tint = "#34C759",
        title = "カレンダー",
        summary = "ライブ・CD リリース・アイドル誕生日を月別に表示。",
        body = listOf(
            HelpItem("スケジュールタブ", "月単位で全アイマスイベントを俯瞰。"),
            HelpItem("ライブ・リリース・誕生日を色分け", "それぞれ別色で表示。タップで詳細にジャンプ。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.PhotoLibrary,
        tint = "#00C7BE",
        title = "画像インポート",
        summary = "アイドル・ブランドのアイコン画像を一括取り込み。",
        body = listOf(
            HelpItem("設定 → キャラクター画像", "JSON で {アイドル名: 画像URL} の形式を渡せば、まとめてダウンロード+保存できます。"),
            HelpItem("型紙 JSON をダウンロード", "アプリ内から型紙 (全アイドル/全ブランド名がキーになった JSON) を書き出せます。それに画像URLを書き足すだけ。"),
            HelpItem("アイドル別名にも対応", "型紙には別名表記も含まれているので、 ロコ でも 伴田路子 でも好きな表記の URL を書けます。"),
            HelpItem("全画像リセット可能", "失敗したり差し替えたい時は「カスタム画像を全削除」でリセットできます。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.CloudSync,
        tint = "#32ADE6",
        title = "同期とアカウント",
        summary = "CloudKit で常に最新のデータ、 Sign in with Apple で編集に参加。",
        body = listOf(
            HelpItem("マスタデータは CloudKit で自動同期", "新しいライブやセトリは CloudKit から差分配信されます。アプリ更新を待たずに最新化されます。"),
            HelpItem("Google ログインは編集用", "閲覧機能には不要。データを編集したい時だけログインしてください。"),
            HelpItem("アカウント削除も可能", "マイページ → アカウントを削除 で、サーバー上の編集履歴とユーザー情報をすべて削除します。"),
        )
    ),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpScreen(onBack: () -> Unit) {
    Scaffold(
        containerColor = DS.bg,
        topBar = {
            TopAppBar(
                title = { Text("使い方", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = DS.bg, titleContentColor = DS.ink, navigationIconContentColor = DS.ink
                )
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Column(modifier = Modifier.padding(horizontal = 4.dp, vertical = 8.dp)) {
                    Text("アイドルライブDB の使い方", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                    Text(
                        "各カテゴリで「こんなことができる」を一覧で紹介しています。気になる項目から覗いてみてください。",
                        fontSize = 13.sp, color = DS.ink2, modifier = Modifier.padding(top = 4.dp)
                    )
                }
            }
            items(HelpCatalog.sections, key = { it.title }) { section -> HelpSectionCard(section) }
        }
    }
}

/** 見出しをタップで開閉する 1 カテゴリ。iOS は遷移だが、Android は戻る操作が増えるので開閉にした。 */
@Composable
private fun HelpSectionCard(section: HelpSection) {
    var expanded by remember { mutableStateOf(false) }
    val theme = ImasTheme.derive(section.tint)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(DS.surface)
            .clickable { expanded = !expanded }
            .animateContentSize()
            .padding(14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(
                section.icon, contentDescription = null, tint = theme.accent,
                modifier = Modifier.size(36.dp).clip(CircleShape).background(theme.bar.copy(alpha = 0.18f)).padding(7.dp)
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(section.title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                Text(section.summary, fontSize = 12.sp, color = DS.ink2)
            }
            Icon(
                if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                contentDescription = null, tint = DS.ink3
            )
        }
        if (expanded) {
            Column(modifier = Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                section.body.forEach { item ->
                    Column {
                        Text(item.label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
                        Text(item.detail, fontSize = 12.sp, color = DS.ink2, modifier = Modifier.padding(top = 2.dp))
                    }
                }
            }
        }
    }
}
