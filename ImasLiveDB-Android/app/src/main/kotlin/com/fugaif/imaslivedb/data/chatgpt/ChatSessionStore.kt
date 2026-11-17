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
    /** バックアップの除外 (res/xml の backup_rules と data_extraction_rules) と同じ名前。変えるときは両方を直す (BackupRulesTest が突き合わせる)。 */
    const val DIRECTORY_NAME = "ChatSessions"

    private fun directory(context: Context): File =
        File(context.filesDir, DIRECTORY_NAME).also { it.mkdirs() }

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
            // 書いている途中で落ちても、読めないファイルが残らないよう、一時ファイルに書いてから置き換える。
            val tmp = File(f.parentFile, "${f.name}.tmp")
            tmp.writeText(chatSessionEncode(session))
            if (!tmp.renameTo(f)) {
                tmp.delete()
                Log.e("ChatSessionStore", "chat_session_save_failed: rename")
            }
        } catch (e: Exception) {
            Log.e("ChatSessionStore", "chat_session_save_failed: ${e.message}")
        }
    }

    fun delete(context: Context, id: String) {
        file(context, id)?.delete()
    }

    fun deleteAll(context: Context) {
        directory(context).listFiles()?.forEach { it.delete() }
    }
}
