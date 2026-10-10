package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

/** Material の記号に無いものを足す置き場。色は使う側の tint で付く (ここの黒は形のためだけ)。 */
object ImasIcons {
    /**
     * コールで震わせるのオフの記号。端末に斜線 (MobileOff) だと「端末が無い」に読めるので、
     * 震える記号 (Vibration) に斜線を引く (iOS `apple.haptics.and.music.note.slash` と対)。
     */
    val VibrationOff: ImageVector by lazy {
        ImageVector.Builder(name = "VibrationOff", defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .addPath(
                PathParser().parsePathString(
                    "M0,15h2L2,9L0,9v6zM3,17h2L5,7L3,7v10zM22,9v6h2L24,9h-2zM19,17h2L21,7h-2v10z" +
                        "M16.5,3h-9C6.67,3 6,3.67 6,4.5v15c0,0.83 0.67,1.5 1.5,1.5h9c0.83,0 1.5,-0.67 1.5,-1.5v-15" +
                        "c0,-0.83 -0.67,-1.5 -1.5,-1.5zM16,19L8,19L8,5h8v14z"
                ).toNodes(),
                fill = SolidColor(Color.Black)
            )
            .addPath(
                PathParser().parsePathString("M2.5,2.5L21.5,21.5").toNodes(),
                stroke = SolidColor(Color.Black),
                strokeLineWidth = 2f,
                strokeLineCap = StrokeCap.Round
            )
            .build()
    }
}
