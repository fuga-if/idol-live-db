# Spotify App Remote SDK (Android)

`spotify-app-remote-release-0.8.0.aar` は Spotify の公式配布物そのまま
(https://github.com/spotify/android-sdk のタグ `v0.8.0-appremote_v2.1.0-auth`、`app-remote-lib/`)。
Maven に出ていないので、ここに置いて `app/build.gradle.kts` から読む。

- ライセンス: Apache License 2.0 (Copyright (c) 2015 Spotify AB)。
- git の blob は配布元と同じ (`ec49aad33b631e3b1066be6ccecb2da528fcc9b9`)。差し替えるときは配布元のタグから取り、同じことを確かめる。
- 使い方は `player/SpotifyLyricsPlayback.kt`。認証は Spotify アプリが行うので、利用者の Spotify アプリ (開発者サイト) に
  このアプリのパッケージ名と署名の SHA-1 を登録してもらう (案内はコアの `spotify_setup_guide`)。
