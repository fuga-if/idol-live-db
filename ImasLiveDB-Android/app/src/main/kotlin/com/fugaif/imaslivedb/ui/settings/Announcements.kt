package com.fugaif.imaslivedb.ui.settings

import android.content.Context
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Abc
import androidx.compose.material.icons.filled.AddAPhoto
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Poll
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * アプリ内蔵のお知らせ (新機能告知)。iOS `Models/Announcement.swift` / `Services/AnnouncementStore.swift` の移植。
 *
 * **サーバー不要**。アプデのたびにこの定数へ 1 件足すだけで増える。既読はローカルに持つ。
 *
 * 本文は iOS のカタログから**機械的に変換**したもので、書き起こしていない。
 * 両 OS でリリースノートが食い違うと、どちらが本当か分からなくなる
 * (直すときは両方直すこと)。アイコンだけは SF Symbol → Material Icons の対応を人が決め、
 * 色は iOS の `Color(red:green:blue:)` を hex に写して `ImasTheme.derive` に渡す。
 */
data class Announcement(
    /** リリースをまたいで安定させる id。既読の記録キーになるので変えないこと。 */
    val id: String,
    val date: String,
    val title: String,
    val summary: String,
    /** 段落。 */
    val body: List<String>,
    val icon: ImageVector,
    /** 装飾テーマ seed (hex)。iOS と同じ色。 */
    val tint: String,
    val link: AnnouncementLink? = null
)

/** お知らせ詳細から開ける遷移先 (任意)。 */
enum class AnnouncementLink { WIDGET_HOW_TO }

object AnnouncementCatalog {
    /** 新しいものほど上 (表示順)。 */
    val all: List<Announcement> = listOf(
        Announcement(
            id = "v1.13.0_readings_android_parity",
            date = "2026-08-28",
            title = "かなで引けるようになりました",
            summary = "曲・会場・ライブ名・作詞作曲の読み仮名を全部入れました。Android 版も iOS に大きく追いつきました。",
            body = listOf(
                "曲名・会場名・ライブ名・作詞作曲の読み仮名を全件そろえました。漢字の曲名をひらがなで打っても見つかります。「おねがいしんでれら」で「お願い！シンデレラ」が出ます。",
                "読みは 1 件ずつ裏取りしました。当て字が多く、素直に読むと外れます。独奏歌=アリア、前奏曲=プレリュード、木苺=ラズベリー、283体操=ツバサ体操、Get lol! Get lol! SONG=げろげろそんぐ。熟語の読み違いも直しました (泥濘=でいねい、傀儡=かいらい、雪月風花=せつげつふうか)。",
                "外部の読み仮名データベースとも全曲を突き合わせました。向こうが正しかったぶんは直し、こちらが正しかったぶんは残しています。",
                "起動時の「今日の1曲」を日替わりにし、奇数日は「今日のアイドル」を出すようにしました。アイドルにもタグを付けてもらえます。",
                "Android 版に通知 (担当の誕生日・ライブ1週間前・チケット締切・月曜予告)、ホーム画面ウィジェット5種、キャラクター画像の取り込み、画像シェアカードを追加しました。",
                "Android 版の絞り込みを iOS と同じところまで広げました。曲は表示形式・アイドル・作詞作曲・シリーズ・CDシリーズ・曲タイプで、ライブは種別・参加状態・お気に入り・メモで絞れます。検索も曲名/アイドル/作詞作曲を切り替えられ、当たった箇所に色が付きます。",
                "セトリの曲が 9 件、統合で消えた曲を指したままになっていたのを直しました。同じ壊れ方を次から検査で捕まえます。",
            ),
            icon = Icons.Filled.Abc,
            tint = "#73C78C",
            link = null
        ),
        Announcement(
            id = "v1.11.0_search_timeline",
            date = "2026-08-24",
            title = "探しかたが変わりました",
            summary = "検索が各一覧の中に入り、絞り込みや並び順とそのまま組み合わせられるようになりました。年表も追加。",
            body = listOf(
                "ライブ・楽曲・アイドルの各一覧に検索欄が付きました。これまでは虫眼鏡を押すと別画面に飛んで、そこで結果が完結してしまい、ブランド絞り込みや並び順と組み合わせられませんでした。今は同じ画面で絞れるので、「シャニマスの曲を配信日順に並べて、そこから名前で絞る」がそのままできます。",
                "曲は曲名だけでなく、アイドル名や作詞・作曲でも探せます。ほかの対象に何件あるかも出るので、「曲名では見つからないけどアイドル名なら97件」がひと目で分かり、そのまま切り替えられます。",
                "検索結果の各行が「なぜ出てきたか」を見せます。当たった箇所に色が付き、アイドルで探したときは当たった名前が、作詞作曲で探したときはその名前が行に出ます。並び順を披露回数順や回収率順にすると、その数字も行に並びます。",
                "見出しと検索欄で2行あったヘッダーを1行に畳みました。一覧が見え始めるまでが近くなっています。絞り込みの動作そのものも12倍速くしました。",
                "プロデュースタブに「年表」を追加。ライブ・楽曲シリーズ・節目を1枚で俯瞰できます。周年やアニメ放映などの節目を34件収録しました。",
                "声優さんの情報を「いつからいつまでが誰」の形に作り直しました。交代のあったアイドルは、歴代のキャストが期間付きで見られます。",
                "週替わりでソロCDが出ていた「SPECIAL SOLO RECORDS」を全468曲そろえました。ギネス世界記録に認定された52週連続リリースの企画です。",
                "アプリアイコンを新しくしました。",
            ),
            icon = Icons.Filled.Search,
            tint = "#6B99E0",
            link = null
        ),
        Announcement(
            id = "v1.10.0_venues_setlist_copy",
            date = "2026-07-27",
            title = "会場から探せる・セトリが見やすく",
            summary = "ライブを会場で絞り込めるように。セトリのシンプル表示と、画面の文字をコピーする機能も追加しました。",
            body = listOf(
                "会場マスタを追加しました。ライブ一覧を会場で絞り込めるほか、公演の会場名やキャパシティが見られます。改名した会場は、その公演当時の名前で表示します。",
                "セトリに「シンプル表示」を追加。曲名だけを詰めて並べるので、現地でさっと確認したり、そのまま共有したりしやすくなりました。",
                "曲名・アイドル名・よみ・CV名などを長押しでコピーできるようになりました。コーレスやタグの説明は、文字を選んで一部だけコピーできます。",
                "ユニット詳細を大幅に拡張。タグ付けや投票の対象になり、画像も登録できます。アイドル一覧はアイドル/ユニットの2タブになりました。",
                "「この曲が好きな人にはこれも」のおすすめを作り直しました。タグがたくさん付いた有名曲ばかり出ていたのを、本当にタグの傾向が近い曲が出るように。開くたびに顔ぶれが変わります。",
                "お気に入り・担当・投票履歴の引き継ぎコードとバックアップに対応しました。機種変更時にご利用ください。",
            ),
            icon = Icons.Filled.Apartment,
            tint = "#73BF99",
            link = null
        ),
        Announcement(
            id = "v1.9.0_idol_tags_community",
            date = "2026-07-10",
            title = "アイドルにもタグ付けできるように",
            summary = "アイドル詳細に「コミュニティ」タブが登場。タグ付けや投票の実績がまとめて見られます。",
            body = listOf(
                "曲だけでなく、アイドルにもみんなでタグを付けられるようになりました。タグはタップで自分の一票をオン/オフ、長押しでそのタグが付いた他の曲・アイドルのランキングが見られます。",
                "アイドル詳細に「コミュニティ」タブを追加。タグ一覧に加えて、「みんなの投票」で過去に獲得した順位 (優勝/第N位) バッジもここにまとまりました。",
                "投票お題への曲候補ピッカーを大幅強化。作詞作曲者やタグ、CDシリーズ、アイドルからも曲を探せるようになり、通常の楽曲一覧と同じ絞り込みが使えます。",
                "プロデュースタブに「タグの動き」を追加。伸びてるタグ・タグが急上昇中の曲やアイドル・最近つけられたタグをまとめてチェックできます。",
            ),
            icon = Icons.Filled.Sell,
            tint = "#66A6D9",
            link = null
        ),
        Announcement(
            id = "v1.8.1_polls_scope",
            date = "2026-06-29",
            title = "投票の候補を絞り込める",
            summary = "ブランド限定や候補リスト指定で、企画ものの「お題」が立てやすくなりました。",
            body = listOf(
                "「お題を投稿」で、投票候補を「全て」「ブランド限定」「候補指定」から選べるようになりました。",
                "ブランド限定: 選んだブランドの曲/アイドルだけが候補。「シャニ限定で好きな曲は？」のような企画に。複数ブランド選択で合同ライブの予想にも。",
                "候補指定: 作成者が候補を直接ピック。「この5曲のうちどれが好き？」のような企画に。最低2件あれば作成可能。",
                "曲のピッカーがリフレッシュ。右上のフィルターから並び順 (五十音 / リリース日 / 披露回数)、ライブ履歴のみ曲を隠す、リミックスを含める、などを切り替えられます。",
                "セトリ予想画面の行間と「歌唱メンバー予想」ボタンの見た目を整理しました。",
                "アイドル詳細のタブを切り替えるとスクロール位置がリセットされるように。",
            ),
            icon = Icons.Filled.Poll,
            tint = "#D966A6",
            link = null
        ),
        Announcement(
            id = "v1.8.0_polls_polish",
            date = "2026-06-27",
            title = "みんなの投票がもっと便利に",
            summary = "ランキングから曲・アイドル詳細へ。優勝した曲には王冠バッジが付きます。",
            body = listOf(
                "「みんなの投票」のランキングから、曲やアイドルをタップして詳細を開けるようになりました。投票受付中のお題は、まだ投票していないものが選ばれて表示されます。",
                "終了したお題で1位になった曲・アイドルには、詳細画面に「優勝」バッジが付くように。タップでそのお題の最終結果も見られます。",
                "楽曲の歌唱メンバー情報を、実際のCD編成に合わせて正確に直しました。",
                "担当・お気に入り・メモを iCloud に自動バックアップ。再インストールや機種変更でも復元されます。",
                "一覧の読み込み表示をスケルトンに変更し、検索・ツールバーの操作感も整えました。",
            ),
            icon = Icons.Filled.BarChart,
            tint = "#F29E1F",
            link = null
        ),
        Announcement(
            id = "v1.7.1_widget_polish",
            date = "2026-06-19",
            title = "スライドショーの画像を選べるように",
            summary = "ウィジェットに出す画像を選べるようになり、アイドル選択も探しやすくなりました。",
            body = listOf(
                "ウィジェットのスライドショーに出す画像を、ギャラリーで1枚ずつ選べるようになりました。サムネを長押しして「スライドショーから外す/入れる」を切り替えられます。お気に入りだけを回すこともできます。",
                "ウィジェット編集でアイドルを選ぶとき、検索で絞り込めるようになり、ブランド名も表示されるようになりました。",
                "ギャラリーの表示や、画像まわりの細かな不具合を修正しました。",
            ),
            icon = Icons.Filled.Widgets,
            tint = "#6680FF",
            link = AnnouncementLink.WIDGET_HOW_TO
        ),
        Announcement(
            id = "v1.7_oshi_widget",
            date = "2026-06-17",
            title = "担当の画像をホーム画面に",
            summary = "ホーム画面ウィジェットに、自分で入れた推しの画像を表示できるようになりました。",
            body = listOf(
                "アイドル詳細の「ギャラリー」に画像を何枚でも追加できるようになりました。先頭の1枚がアイコンになります。",
                "ホーム画面ウィジェット「担当の画像」を追加すると、選んだアイドルの画像を表示。タップで次の画像に切り替わり、放っておいても自動でローテーションします。",
                "「タップでアプリ」版もあるので、お気に入りの起動ショートカットとしても使えます。",
            ),
            icon = Icons.Filled.AddAPhoto,
            tint = "#FF4C8C",
            link = AnnouncementLink.WIDGET_HOW_TO
        ),
    )
}

/**
 * お知らせの既読状態をローカルに持つ。サーバー不要。
 *
 * 保存キーは iOS の `AnnouncementDefaults` と同じ名前にしてある。同じ端末で
 * 両方を使うことは無いが、名前が揃っていないと「どちらの実装の話か」を
 * コードから追えなくなる。
 */
class AnnouncementStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun readIds(): Set<String> = prefs.getStringSet(KEY_READ, emptySet()) ?: emptySet()

    fun isRead(id: String): Boolean = id in readIds()

    val unreadCount: Int
        get() = readIds().let { read -> AnnouncementCatalog.all.count { it.id !in read } }

    fun markRead(id: String) {
        val next = readIds() + id
        // getStringSet が返す Set は SharedPreferences の内部インスタンスなので、
        // 直接いじらず新しい Set を渡す (in-place 変更は次回読み出しまで反映されない)。
        prefs.edit().putStringSet(KEY_READ, next).apply()
    }

    fun markAllRead() {
        prefs.edit().putStringSet(KEY_READ, AnnouncementCatalog.all.map { it.id }.toSet()).apply()
    }

    /**
     * アプリのバージョンが前回起動から変わっていて、かつ未読があるときだけ true。
     * 一度判定したらそのバージョンを記録し、同バージョンでは二度と自動表示しない。
     * 初インストール (記録なし) は自動表示しない — 初回はオンボーディングの領分。
     */
    fun shouldAutoShowOnUpdate(currentVersion: String): Boolean {
        val lastSeen = prefs.getString(KEY_SEEN_VERSION, null)
        if (lastSeen == currentVersion) return false
        prefs.edit().putString(KEY_SEEN_VERSION, currentVersion).apply()
        if (lastSeen == null) return false
        return unreadCount > 0
    }

    private companion object {
        const val PREFS_NAME = "announcements"
        const val KEY_READ = "announce_read_ids"
        const val KEY_SEEN_VERSION = "announce_seen_version"
    }
}
