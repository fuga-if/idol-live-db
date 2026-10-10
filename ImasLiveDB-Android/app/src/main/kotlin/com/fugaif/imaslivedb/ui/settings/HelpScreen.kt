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
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import com.fugaif.imaslivedb.ui.designsystem.ImasDisclosureRow
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasListSection
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.DS

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
 *
 * iOS は各カテゴリを別画面へ遷移して見せるが、Android は戻る操作が増えるので
 * その場で開閉する形にしている (既存の意図的な差。押し戻さない)。
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
            HelpItem("ライブの種別で見分ける", "周年ライブ・オーケストラ・他社イベント・リリースイベント・バースデーライブなどの種別が付いています。絞り込みで種別ごとに外すこともできます。"),
            HelpItem("詳細でセトリ・出演者・チケット情報を確認", "ライブをタップすると、公演日ごとのセトリ、出演アイドル、参考動画、チケット情報まで確認できます。"),
            HelpItem("参加したライブを記録", "公演の行を右にスワイプすると、その場で参加 (現地 / 配信 / LV) を登録できます。現地で見て配信のアーカイブも買った公演のように、形態は複数付けられます (チケット代も形態ごとに記録できます)。詳細画面からも付けられ、マイページの参加カウントに加算されます。"),
            HelpItem("衣装と着用公演", "イベント詳細の「情報」タブに、そのイベントで着た衣装がまとまっています。衣装を開くと、ほかのイベントも含めてその衣装を着た公演と曲をたどれます。"),
            HelpItem("開催前のセトリ予想", "開催前の公演では、みんなの予想に加えて、過去のセトリから推定した「機械予測」が出ます。気になる曲はそのまま自分の予想に入れられます。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.FormatListNumbered,
        tint = "#FF6B3D",
        title = "セットリストの見方",
        summary = "曲ごとの「いつぶり」や自分の回収を、セトリの行で確かめられます。",
        body = listOf(
            HelpItem("シンプル / 普通 / 詳細 の 3 つの表示", "セトリ右上の「その他」メニューから選べます。シンプルは曲名と歌った人だけ、詳細は自分の回収まで行に出します。"),
            HelpItem("「初披露」「3 年 10 か月ぶり」", "その曲が前にいつ歌われたかを出します。数えるのはその公演の時点なので、昔のライブを開くと当時の間隔が出ます。1 か月未満は「12 日ぶり」のように日数で出します。"),
            HelpItem("自分の回収を重ねる", "詳細表示では「初回収」「回収 3 回目」「未回収」が行に出て、セトリの上に「この公演で 12 曲回収」のような要約が出ます。"),
            HelpItem("オリメンにとって何回目か", "カバーや別ユニットで歌われた曲には、歌った本人にとって何回目か (オリメン 4 回目 など) を添えます。"),
            HelpItem("数えない公演", "会場の舞台が無い配信だけのライブと MV 上映会は、セトリには並びますが、披露回数・いつぶり・回収には数えません。"),
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
            HelpItem("Spotify 連携", "自分の Spotify アプリの Client ID で連携すると、曲を Spotify でフル尺で鳴らして歌詞を追いかけられます (Spotify Premium が要ります)。セトリや自分のプレイリストを Spotify に書き出すこともできます。始め方は使い方の「Spotify と連携する」に図つきで載っています。"),
            HelpItem("オリジナルメンバーを表示", "曲のアイコン群はオリジナル歌唱メンバー (ライブ歌唱者ではなく)。ユニット曲はユニット名で表示されます。"),
            HelpItem("回収済 / 未回収で絞り込み", "マイマークで「回収済」を付けた曲だけ、または未回収だけを表示できます。"),
            HelpItem("並びはリリース日順", "既定はリリース日の新しい順です。件数の行にある並び替えメニューから、披露回数順などにすぐ切り替えられます。"),
            HelpItem("曲の補足", "曲名の下に、その曲についての補足が出ます。ログインすれば曲詳細から補足を書いたり直したりできます。"),
            HelpItem("KAMISABI の収録曲", "絞り込みで「KAMISABI収録曲のみ」を選ぶと収録曲だけになります。カードの所持も記録でき、収録率が分かります。"),
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
            HelpItem("アイドル詳細で担当曲・出演ライブを確認", "アイドルをタップすると、担当曲・出演ライブ・誕生日・カラーが見られます。担当曲はソロ・ユニット・全体曲・カバーの小タブで切り替えられます。"),
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
        icon = Icons.Filled.AttachMoney,
        tint = "#16A34A",
        title = "収支（家計簿）",
        summary = "チケット代・交通費・グッズ代など、アイマスに使ったお金を記録できます。",
        body = listOf(
            HelpItem("プロデュースタブの「収支」から", "日付と金額と費目 (チケット・交通・宿・グッズ・課金 など) で記録します。月別・年別の合計と費目ごとの内訳が出ます。"),
            HelpItem("公演に紐づける", "支出を公演に紐づけると、「この遠征でいくら使ったか」と 1 公演あたりの額が分かります。課金や通販は紐づけずに同じ帳簿へ入れられます。"),
            HelpItem("チケット代を自動で聞く", "参加を付けたとき、チケット価格が分かっている公演ならその額で記録するかを確認します。過去の参加から、まだ記録していないチケット代をまとめて取り込むこともできます。"),
            HelpItem("端末の中だけに保存", "収支はサーバーに送らず、端末の中だけに保存します。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.BarChart,
        tint = "#0EA5E9",
        title = "習熟度",
        summary = "曲ごとの覚え具合を付けて、シリーズやユニットごとにどこまで覚えたかを確かめられます。",
        body = listOf(
            HelpItem("プロデュースタブの「習熟度」から", "シリーズ・ユニット・年代ごとに曲がまとまっていて、あと何曲覚えればいいかが分かります。"),
            HelpItem("1 タップで段階を上げる", "曲の行から 1 タップで段階を上げられます。右にスワイプでも上げられ、下げたり特定の段へ飛ばすのは長押しのピッカーから選べます。"),
            HelpItem("段階は自分で決める", "設定の「習熟度」で、段の数 (2〜4 段) と呼び名を変えられます。呼び名を変えても、付けた記録はそのまま残ります。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.Edit,
        tint = "#007AFF",
        title = "みんなで編集",
        summary = "ログインすればセトリ・楽曲・ライブ情報を直接編集でき、その場で全員に反映されます。",
        body = listOf(
            HelpItem("直接編集して、すぐ反映", "承認待ちはありません。ログインユーザーがセトリ・新曲・新イベント・参考動画などを直接追加・修正でき、CloudKit 経由ですぐ全員の端末に届きます。Wikipedia のような共同編集スタイルです。"),
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
        icon = Icons.Filled.SportsEsports,
        tint = "#FF2D55",
        title = "クイズ・ゲーム",
        summary = "プロデュースタブの「クイズ・ゲーム」で 5 種類のクイズが遊べます。",
        body = listOf(
            HelpItem("5 種類のクイズ", "アイドル当て・ソロ曲クイズ・セトリ当て・イントロドン・メンバーカラー合わせがあります。"),
            HelpItem("セトリ当て", "実際の公演のセトリの空欄に入る曲を 4 択で当てます。"),
            HelpItem("累計ポイントと「つづきから」", "遊ぶほどポイントが貯まります。途中でやめても「つづきから」で再開できます。結果は画像にしてシェアできます。"),
            HelpItem("イントロドンは配信のある曲で遊べる", "出題は 30 秒のプレビュー再生です。配信のある曲だけが出題対象になります。"),
            HelpItem("ブランド・難易度を選択", "出題するブランドを選べます。イントロドンは再生秒数で難易度を調整できます。"),
        )
    ),
    HelpSection(
        icon = Icons.Filled.Search,
        tint = "#8E8E93",
        title = "検索",
        summary = "ライブ・楽曲・アイドルの各一覧の検索欄から、その場で絞り込めます。",
        body = listOf(
            HelpItem("一覧の中で絞り込む", "ライブ / 楽曲 / アイドル 各タブの検索欄は、いま表示中の一覧をその場で絞り込みます。ブランドの絞り込みや並び順と組み合わせられます。"),
            HelpItem("何で探すかを切り替える", "楽曲は曲名・アイドル名・作詞作曲者、アイドルはアイドル名と CV 名を切り替えて探せます。打っている間、それぞれ何件当たるかが出ます。"),
            HelpItem("ほかのタブの件数", "「ライブに 8」のように、同じ語がほかのタブで何件当たるかも出ます。押すとそのタブへ移って同じ語で絞り込みます。"),
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

/** 使い方の特集 (図つきの手順の画面)。 */
private enum class HelpFeature { SPOTIFY, SPOTIFY_SETTINGS }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpScreen(onBack: () -> Unit) {
    var feature by remember { mutableStateOf<HelpFeature?>(null) }
    when (feature) {
        HelpFeature.SPOTIFY -> {
            SpotifyHowToScreen(onBack = { feature = null }, onOpenSettings = { feature = HelpFeature.SPOTIFY_SETTINGS })
            return
        }
        HelpFeature.SPOTIFY_SETTINGS -> {
            SpotifySettingsScreen(onBack = { feature = HelpFeature.SPOTIFY })
            return
        }
        null -> Unit
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("使い方") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
                    }
                }
            )
        }
    ) { padding ->
        ImasFormBackdrop(modifier = Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                ImasListSection {
                    Column(
                        Modifier.padding(vertical = DS.Space.gapTight),
                        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
                    ) {
                        Text("アイドルライブDB の使い方", style = ImasTextRole.CARD_TITLE.style, color = ImasTextRole.CARD_TITLE.color)
                        Text(
                            "各カテゴリで「こんなことができる」を一覧で紹介しています。気になる項目から覗いてみてください。",
                            style = ImasTextRole.ROW_SUBTITLE.style,
                            color = ImasTextRole.ROW_SUBTITLE.color
                        )
                    }
                }
                ImasListSection("特集") {
                    ImasNavRow(
                        title = "Spotify と連携する",
                        subtitle = "自分の Spotify アプリを作って、セトリを Spotify のプレイリストに。図つきで手順を案内します。",
                        subtitleLineLimit = 2,
                        icon = Icons.Filled.QueueMusic,
                        onClick = { feature = HelpFeature.SPOTIFY },
                    )
                }
                ImasListSection("機能カテゴリ") {
                    HelpCatalog.sections.forEach { section -> HelpSectionDisclosure(section) }
                }
            }
        }
    }
}

/**
 * 1 機能カテゴリ。見出しをタップで開閉する (§5.15 `ImasDisclosureRow`)。
 * iOS は遷移だが、Android は戻る操作が増えるのでその場の開閉にしている (既存の意図的な差)。
 */
@Composable
private fun HelpSectionDisclosure(section: HelpSection) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        ImasDisclosureRow(
            title = section.title,
            subtitle = section.summary,
            subtitleLineLimit = Int.MAX_VALUE,
            icon = section.icon,
            iconTone = ImasIconTileTone.THEMED,
            seed = section.tint,
            isExpanded = expanded,
            onToggle = { expanded = !expanded }
        )
        if (expanded) {
            Column(
                Modifier
                    .clickable { expanded = !expanded }
                    .padding(start = DS.Space.rowH, end = DS.Space.rowH, bottom = DS.Space.rowV),
                verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
            ) {
                section.body.forEach { item ->
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                        Text(item.label, style = ImasTextRole.ROW_TITLE.style, color = ImasTextRole.ROW_TITLE.color)
                        Text(item.detail, style = ImasTextRole.ROW_SUBTITLE.style, color = ImasTextRole.ROW_SUBTITLE.color)
                    }
                }
            }
        }
    }
}
