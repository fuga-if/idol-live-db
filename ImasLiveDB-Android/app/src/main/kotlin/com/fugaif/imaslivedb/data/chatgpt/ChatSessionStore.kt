package com.fugaif.imaslivedb.data.chatgpt

import android.content.Context
import android.util.Log
import java.io.File
import uniffi.imas_core.ChatSession
import uniffi.imas_core.ChatSessionSummary
import uniffi.imas_core.chatSessionDecode
import uniffi.imas_core.chatSessionEncode
import uniffi.imas_core.chatSessionShelf

/**
 * チャットの会話を端末のファイルに置く。iOS `ChatSessionStore`。
 *
 * 保存の形・題・何本まで残すか・一覧の並びはコア (`domain::chat_sessions`)。ここはファイルを
 * 読む・書く・消すだけ。置き場はアプリの専用領域 (`filesDir/ChatSessions/<id>.json`) で、サーバには送らない。
 * ファイルを触るので、メインスレッドから呼ばない。
 */
object ChatSessionStore {
    private fun directory(context: Context): File =
        File(context.filesDir, "ChatSessions").also { it.mkdirs() }

    private fun file(context: Context, id: String): File? {
        // id は自分で振った UUID。念のため、パスに使えない字が混ざったものは扱わない。
        if (id.isEmpty() || !id.all { it.isLetterOrDigit() || it == '-' }) return null
        return File(directory(context), "$id.json")
    }

    private fun files(context: Context): List<File> =
        directory(context).listFiles { f -> f.extension == "json" }?.toList().orEmpty()

    /** 一覧 (新しい順)。上限を越えた古い会話は、ここで消す。 */
    fun list(context: Context): List<ChatSessionSummary> {
        val sessions = files(context).mapNotNull { f ->
            runCatching { chatSessionDecode(f.readText()) }.getOrNull()
        }
        val shelf = chatSessionShelf(sessions)
        shelf.overflowIds.forEach { delete(context, it) }
        return shelf.sessions
    }

    fun load(context: Context, id: String): ChatSession? {
        val f = file(context, id) ?: return null
        return runCatching { chatSessionDecode(f.readText()) }.getOrNull()
    }

    fun save(context: Context, session: ChatSession) {
        val f = file(context, session.id) ?: return
        try {
            f.writeText(chatSessionEncode(session))
        } catch (e: Exception) {
            Log.e("ChatSessionStore", "chat_session_save_failed: ${e.message}")
        }
    }

    fun delete(context: Context, id: String) {
        file(context, id)?.delete()
    }

    fun deleteAll(context: Context) {
        files(context).forEach { it.delete() }
    }
}
