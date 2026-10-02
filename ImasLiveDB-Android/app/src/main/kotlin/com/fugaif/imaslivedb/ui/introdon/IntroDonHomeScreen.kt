package com.fugaif.imaslivedb.ui.introdon

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasMasthead
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasSetupHeader

/**
 * イントロドンのホーム画面。iOS IntroDonHomeView の移植。
 *
 * iOS 版は Apple Music (MusicKit) のフル再生 (実イントロを頭出し) を使えるが、Android には
 * 同等のカタログストリーミング手段が無いため、常に楽曲の `preview_url` (30秒プレビュー) で
 * イントロを再現する。フル再生/プレビュー切替 UI は Android では意味を持たないため省略し、
 * 代わりにその旨を伝える案内 (`ImasNotice`) を出す。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IntroDonHomeScreen(onBack: () -> Unit, onNavigateToSetup: () -> Unit = {}) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("イントロドン") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") } }
            )
        }
    ) { padding ->
        ImasPage(modifier = Modifier.padding(padding)) {
            ImasMasthead("INTRO DON")
            ImasSetupHeader(
                icon = Icons.Filled.MusicNote,
                title = "イントロドン",
                message = "曲のイントロを聴いて\n曲名をいち早く当てよう"
            )
            ImasButton(
                title = "ゲームをはじめる",
                onClick = onNavigateToSetup,
                role = ImasButtonRole.PRIMARY,
                size = ImasButtonSize.LARGE,
                fillsWidth = true
            )
            ImasNotice(
                kind = ImasNoticeKind.INFO,
                title = "プレビュー再生で出題します",
                message = "各曲の30秒プレビューからイントロ部分を再生します。プレビューを持たない曲は出題対象外です。"
            )
        }
    }
}
