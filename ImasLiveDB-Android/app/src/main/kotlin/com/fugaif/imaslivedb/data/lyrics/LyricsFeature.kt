package com.fugaif.imaslivedb.data.lyrics

/**
 * 歌詞タブ (= コールガイド) を画面に出してよいか。iOS `Services/LyricsFeature.swift` と対。
 *
 * **2026-10-06 から閉じている。** 歌詞データの取得方法に問題があったため、掲載していた歌詞を
 * サーバから全て削除した。許諾は生きているので、入手方法を作り直したらここを `true` に戻す。
 * 閉じている間は歌詞タブ・歌詞検索・歌詞クイズ・コールガイドの入口を出さない
 * (Android には歌詞検索・コールガイド・歌詞クイズはもともと無いので、歌詞タブと
 * 再生中バーの追従だけが対象)。
 */
object LyricsFeature {
    const val isAvailable: Boolean = false

    /**
     * 歌詞の投稿 ([com.fugaif.imaslivedb.ui.lyrics.LyricSubmissionScreen]) を受け付けるか。
     * 表示 ([isAvailable]) とは別に、閉じている間も投稿だけ先に集められるようにする。
     * サーバの受け口 (`POST /songs/:id/lyric-submissions`) を本番に出すまでは開発ビルドだけ。
     */
    val acceptsSubmissions: Boolean get() = com.fugaif.imaslivedb.BuildConfig.DEBUG
}
