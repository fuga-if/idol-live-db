package com.fugaif.imaslivedb.data.community

import android.content.Context
import java.util.UUID

/** X-Device-Id 用の端末永続 UUID (集計系コミュニティの device 重複排除/レート制限のキー)。 */
object DeviceIdentity {
    private const val PREFS = "imas_device"
    private const val KEY = "device_id"

    @Volatile private var cached: String? = null

    fun get(context: Context): String {
        cached?.let { return it }
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        var id = prefs.getString(KEY, null)
        if (id == null) {
            id = UUID.randomUUID().toString()
            prefs.edit().putString(KEY, id).apply()
        }
        cached = id
        return id
    }
}
