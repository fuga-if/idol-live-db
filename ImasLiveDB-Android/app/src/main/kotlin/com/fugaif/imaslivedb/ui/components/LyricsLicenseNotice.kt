package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.lyrics.JASRACLicense
import com.fugaif.imaslivedb.data.lyrics.NexToneLicense
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.DS

/** 原本のマークの下に、この Android 版の許諾番号を表示する。 */
@Composable
fun LyricsLicenseNotice(compact: Boolean = false) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = if (compact) DS.sp1 else DS.sp5),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DS.sp2)
    ) {
        androidx.compose.foundation.Image(
            painter = androidx.compose.ui.res.painterResource(id = com.fugaif.imaslivedb.R.drawable.jasrac_mark),
            contentDescription = null,
            modifier = Modifier.height(28.dp).width(28.dp)
        )
        ImasText(JASRACLicense.NOTICE, ImasTextRole.META)
        if (!compact) {
            androidx.compose.foundation.Image(
                painter = androidx.compose.ui.res.painterResource(id = com.fugaif.imaslivedb.R.drawable.nextone_mark),
                contentDescription = null,
                modifier = Modifier.height(28.dp).width(28.dp)
            )
            ImasText(NexToneLicense.NOTICE, ImasTextRole.META)
        }
    }
}
