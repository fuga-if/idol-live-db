package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasProse
import com.fugaif.imaslivedb.ui.designsystem.ImasProseBlock
import com.fugaif.imaslivedb.ui.settings.InfoScreenScaffold
import uniffi.imas_core.LyricGuideBlock
import uniffi.imas_core.lyricSubmissionGuideline

/**
 * 歌詞の投稿ガイドライン (読みもの)。iOS `LyricSubmissionGuideView` の移植。
 * 中身はコア ([lyricSubmissionGuideline]) が持ち、ここは並べるだけ。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LyricSubmissionGuideScreen(onBack: () -> Unit) {
    InfoScreenScaffold(title = "投稿ガイドライン", onBack = onBack) {
        ImasPage {
            ImasProse(blocks = lyricSubmissionGuideline().map(::toProseBlock))
        }
    }
}

private fun toProseBlock(block: LyricGuideBlock): ImasProseBlock = when (block) {
    is LyricGuideBlock.Heading -> ImasProseBlock.Heading(block.text)
    is LyricGuideBlock.Paragraph -> ImasProseBlock.Paragraph(block.text)
    is LyricGuideBlock.Bullets -> ImasProseBlock.Bullets(block.items)
    is LyricGuideBlock.Note -> ImasProseBlock.Note(block.text)
}
