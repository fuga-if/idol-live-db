package com.fugaif.imaslivedb.data.auth

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.fugaif.imaslivedb.data.net.SessionRenewer
import com.fugaif.imaslivedb.data.net.UrlConnectionTransport
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import com.fugaif.imaslivedb.data.net.WorkerTransport
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import org.json.JSONObject
import uniffi.imas_core.SessionResponse
import uniffi.imas_core.StoredAuthState
import uniffi.imas_core.authAdoptSessionResponse
import uniffi.imas_core.authRestoreStoredState
import uniffi.imas_core.authSessionRefreshCandidate
import uniffi.imas_core.authStoredFlagValue
import java.security.KeyStore

data class AuthState(
    val isSignedIn: Boolean = false,
    val displayName: String? = null,
    val isAdmin: Boolean = false,
    /**
     * サーバ側で BAN 済みか。BAN 済みには編集/投稿導線を出さない (判定は [editPermissionRules] 経由でコアへ)。
     *
     * `/auth/login` のレスポンスにこの項目は無い契約なので、供給元は iOS と同じ 2 経路:
     * 起動時の [AuthService.refreshMe] (`GET /auth/me`) と、編集 API が 403 を返した時の
     * [AuthService.markBannedFromServer]。
     */
    val isBanned: Boolean = false
)

/**
 * Sign in with Google (Credential Manager) → サーバの /auth/login でセッションJWTに交換。
 * iOS の AuthService (Sign in with Apple) の Android 版。
 * サーバ側の投票等の認証必須エンドポイントは、iOS/Android どちらでも同じセッションJWT形式を検証する。
 */
class AuthService(
    private val appContext: Context,
    transport: WorkerTransport = UrlConnectionTransport,
    /** 暗号化 prefs を開く。テストは失敗や成功を差し替える。 */
    openSecurePrefs: (Context) -> SharedPreferences = ::openEncryptedPrefs
) : SessionRenewer {

    private val http = WorkerHttpClient(appContext, { sessionToken }, transport, renewer = this)

    // Android の Credential Manager (GetGoogleIdOption) は serverClientId に渡した
    // Web アプリケーション用クライアント ID を id トークンの aud に埋め込む仕様。
    // サーバの GOOGLE_WEB_CLIENT_ID と一致させること。
    private val webClientId =
        "612236234738-q1ku8tnnf4ce9jm1q006jp45k6mmmluc.apps.googleusercontent.com"

    /**
     * セッション JWT などを置く暗号化 prefs (`imas_auth_secure`、バックアップ対象外)。
     *
     * キーストアの鍵と合わなくなった端末 (復元・鍵の破損) では開けずに例外になる。
     * ただしキーストアの一時的な失敗もあるので、まず消さずに 1 回だけ開き直す
     * (いきなり消すと、一時的な失敗でサインアウトしてしまう)。それでも開けなければ、
     * 壊れた保存先は読めないので消して開き直し、未サインインとして続ける
     * (null のまま動くと、サインインしても保存先が無く、起動のたびにサインインし直しになる)。
     * 消しても開けなければ null にして、未サインインのまま動かす (起動では落とさない)。
     */
    private val prefs: SharedPreferences? = try {
        openSecurePrefs(appContext)
    } catch (e: Exception) {
        Log.w(TAG, "認証情報の保存先を開けない → 消さずに開き直す", e)
        try {
            openSecurePrefs(appContext)
        } catch (e: Exception) {
            Log.e(TAG, "開き直しても開けない → 消して開き直す", e)
            resetSecurePrefs(appContext)
            try {
                openSecurePrefs(appContext)
            } catch (e: Exception) {
                Log.e(TAG, "消しても開けない → 未サインインとして続ける", e)
                null
            }
        }
    }

    val sessionToken: String? get() = prefs?.getString(KEY_SESSION_TOKEN, null)

    private val _state = MutableStateFlow(
        prefs?.let {
            AuthState(
                isSignedIn = sessionToken != null,
                displayName = it.getString(KEY_DISPLAY_NAME, null),
                isAdmin = it.getBoolean(KEY_IS_ADMIN, false),
                // 起動直後 (refreshMe が返る前) にも編集導線を畳めるよう、前回判明した BAN を復元する。
                isBanned = it.getBoolean(KEY_IS_BANNED, false)
            )
        } ?: AuthState()
    )
    val state: StateFlow<AuthState> = _state.asStateFlow()

    /** activityContext は UI (アカウント選択シート) を出すため Activity context が必要。 */
    suspend fun signIn(activityContext: Context): Result<Unit> = withContext(Dispatchers.Main) {
        try {
            val googleIdOption = GetGoogleIdOption.Builder()
                .setFilterByAuthorizedAccounts(false)
                .setServerClientId(webClientId)
                .build()
            val request = GetCredentialRequest.Builder()
                .addCredentialOption(googleIdOption)
                .build()
            val credentialManager = CredentialManager.create(activityContext)
            val response = credentialManager.getCredential(activityContext, request)
            val credential = response.credential
            if (credential !is CustomCredential ||
                credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
            ) {
                return@withContext Result.failure(IllegalStateException("unexpected credential type"))
            }
            val googleIdToken = GoogleIdTokenCredential.createFrom(credential.data).idToken
            exchangeForSession(googleIdToken)
        } catch (e: Exception) {
            Log.w(TAG, "signIn failed: ${e.message}")
            Result.failure(e)
        }
    }

    fun signOut() {
        prefs?.edit()?.clear()?.apply()
        _state.value = AuthState()
    }

    /**
     * `GET /auth/me` で isAdmin / isBanned / displayName を最新化する。
     * iOS `AuthService.refreshMe` と同じ契約 (レスポンスは素の camelCase)。
     *
     * BAN はサーバ側でしか立たず `/auth/login` は isBanned を返さないので、
     * この再取得が無いと BAN 済みユーザーに編集導線が出続ける。
     * 呼ぶのはアプリが前面に出たとき ([refreshMeIfDue])。iOS は起動時。
     */
    suspend fun refreshMe(): Unit = withContext(Dispatchers.IO) {
        if (sessionToken == null) return@withContext
        try {
            val response = http.request("GET", "/auth/me")
            val code = response.code
            val text = response.body
            if (!response.isSuccess || text.isNullOrEmpty()) {
                // 401 は送信の口 (WorkerHttpClient) が再発行を 1 回試し、それでも通らなければ
                // セッションを失効させている ([renewAfterUnauthorized])。ここは記録だけ。
                Log.w(TAG, "auth/me -> HTTP $code body=$text")
                return@withContext
            }
            val json = JSONObject(text)
            val isAdmin = json.optBoolean("isAdmin", false)
            val isBanned = json.optBoolean("isBanned", false)
            // JSON null は optString が "null" 文字列で返すので isNull で先に弾く。
            val displayName =
                if (json.isNull("displayName")) null else json.optString("displayName").ifEmpty { null }
            prefs?.edit()?.let { editor ->
                editor.putBoolean(KEY_IS_ADMIN, isAdmin).putBoolean(KEY_IS_BANNED, isBanned)
                if (displayName != null) editor.putString(KEY_DISPLAY_NAME, displayName)
                editor.apply()
            }
            _state.value = _state.value.copy(
                isAdmin = isAdmin,
                isBanned = isBanned,
                displayName = displayName ?: _state.value.displayName
            )
        } catch (e: Exception) {
            Log.w(TAG, "refreshMe failed: ${e.message}")
        }
    }

    /** 直近に [refreshMe] を問い合わせた時刻 (このプロセスの中だけ)。0 = まだ。 */
    @Volatile private var lastMeRefreshMs = 0L

    /**
     * アプリが前面に出たときに呼ぶ。このプロセスで [ME_REFRESH_INTERVAL_MS] 以内に
     * 問い合わせていれば何もしない (前面に出るたびにサーバを読まないため)。
     */
    suspend fun refreshMeIfDue(nowMs: Long = System.currentTimeMillis()) {
        if (lastMeRefreshMs != 0L && nowMs - lastMeRefreshMs < ME_REFRESH_INTERVAL_MS) return
        lastMeRefreshMs = nowMs
        refreshMe()
    }

    /**
     * 編集系 API が 403 を返した時に呼ぶ (= BAN の可能性が高い)。
     * 次回起動の [refreshMe] を待たずローカルへ反映し、その場で編集導線を畳む。
     * iOS `AuthService.markBannedFromServer` と同じ best-effort 反映。
     */
    fun markBannedFromServer() {
        prefs?.edit()?.putBoolean(KEY_IS_BANNED, true)?.apply()
        _state.value = _state.value.copy(isBanned = true)
    }

    // MARK: - セッションの再発行 (iOS `AuthService.refreshSession` と同じ条件)

    /** 再発行を 1 つずつにする (401 が同時に何本も返っても `/auth/refresh` は 1 回)。 */
    private val refreshLock = Any()

    /**
     * 送信の口が 401 を受けたときに呼ぶ ([SessionRenewer])。`/auth/refresh` で再発行を試し、
     * 通らなければセッションを失効させる (iOS の `handleSessionExpired` と同じく、
     * サインイン済みの表示を落としてログイン導線に戻す)。
     */
    override fun renewAfterUnauthorized(rejectedToken: String): Boolean = synchronized(refreshLock) {
        val current = sessionToken
        // 待っている間に別のリクエストが再発行を済ませていれば、それで送り直す。
        if (current != null && current != rejectedToken) return true
        if (performSessionRefresh(nowEpochSeconds())) return true
        expireSession()
        false
    }

    /**
     * アプリが前面に出たときに呼ぶ。保存しているセッションの期限を見て (判断はコアの
     * `authRestoreStoredState`)、期限が近い・切れても猶予内なら再発行し、
     * 再発行も望めない形なら捨てる。JWT の期限は 1 年で、再発行しないと 1 年後に
     * 画面はサインイン済みのまま書き込みが 401 で失敗し続けていた。
     */
    suspend fun refreshSessionIfDue(nowEpochSeconds: Long = nowEpochSeconds()): Unit = withContext(Dispatchers.IO) {
        val prefs = prefs ?: return@withContext
        val stored = prefs.getString(KEY_SESSION_TOKEN, null) ?: return@withContext
        val restored = authRestoreStoredState(
            StoredAuthState(
                // Android はユーザー ID を保存しておらず、セッションの有無がサインインの有無。
                userId = SIGNED_IN_MARKER,
                identityToken = null,
                sessionToken = stored,
                isAdminFlag = authStoredFlagValue(prefs.getBoolean(KEY_IS_ADMIN, false)),
                isBannedFlag = authStoredFlagValue(prefs.getBoolean(KEY_IS_BANNED, false))
            ),
            nowEpochSeconds
        )
        synchronized(refreshLock) {
            // 待っている間に再発行・サインアウトが済んでいれば何もしない。
            if (sessionToken != stored) return@synchronized
            when {
                restored.shouldDeleteStoredSessionToken -> expireSession()
                restored.shouldRefreshSession -> performSessionRefresh(nowEpochSeconds)
            }
        }
    }

    /** `/auth/refresh` で再発行し、採用できたら保存する。採否はコアが決める。 */
    private fun performSessionRefresh(nowEpochSeconds: Long): Boolean {
        val prefs = prefs ?: return false
        val token = authSessionRefreshCandidate(sessionToken, prefs.getString(KEY_SESSION_TOKEN, null))
            ?: return false
        return try {
            val response = http.request("POST", "/auth/refresh", bearer = token)
            val text = response.body
            if (!response.isSuccess || text.isNullOrEmpty()) {
                Log.w(TAG, "auth/refresh -> HTTP ${response.code}")
                return false
            }
            val json = JSONObject(text)
            val adoption = authAdoptSessionResponse(
                SessionResponse(json.getString("sessionToken"), json.optBoolean("isAdmin", false), null),
                nowEpochSeconds
            )
            if (!adoption.accepted) {
                Log.w(TAG, "session_refresh_rejected_invalid_claims")
                return false
            }
            prefs.edit().apply {
                adoption.sessionToken?.let { putString(KEY_SESSION_TOKEN, it) }
                adoption.isAdmin?.let { putBoolean(KEY_IS_ADMIN, it) }
                adoption.displayName?.let { putString(KEY_DISPLAY_NAME, it) }
            }.apply()
            _state.value = _state.value.let {
                it.copy(
                    isSignedIn = adoption.isSignedIn ?: it.isSignedIn,
                    isAdmin = adoption.isAdmin ?: it.isAdmin,
                    displayName = adoption.displayName ?: it.displayName
                )
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "session refresh failed: ${e.message}")
            false
        }
    }

    /** 再発行もできずにセッションが失効した。表示名は次のサインインまで残す (iOS と同じ)。 */
    private fun expireSession() {
        prefs?.edit()?.remove(KEY_SESSION_TOKEN)?.apply()
        _state.value = _state.value.copy(isSignedIn = false)
    }

    /** 表示名を変更する (`POST /users/me`)。iOS `AuthService.updateDisplayName` と同じ契約。 */
    suspend fun updateDisplayName(name: String): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val body = JSONObject().put("display_name", name)
            requestVoid("POST", "/users/me", body)
            prefs?.edit()?.putString(KEY_DISPLAY_NAME, name)?.apply()
            _state.value = _state.value.copy(displayName = name)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * App Store/Play Store のアカウント削除要件対応:
     * サーバー上の本人データ (投稿・投票・予想・rate limit・user レコード) を削除した上でサインアウトする。
     * iOS `AuthService.deleteAccount` と同じ契約 (`DELETE /users/me`)。
     */
    suspend fun deleteAccount(): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            requestVoid("DELETE", "/users/me", null)
            signOut()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private fun requestVoid(method: String, path: String, body: JSONObject?) {
        val response = http.request(method, path, body)
        if (!response.isSuccess) {
            Log.w(TAG, "$method $path -> HTTP ${response.code} body=${response.body}")
            throw IllegalStateException("HTTP ${response.code}")
        }
    }

    private suspend fun exchangeForSession(googleIdToken: String): Result<Unit> =
        withContext(Dispatchers.IO) {
            // 保存先が開けない端末では、セッションを持てないのでサインインを完了させない。
            val prefs = prefs ?: return@withContext Result.failure(
                IllegalStateException("この端末ではサインイン情報を保存できません")
            )
            try {
                // サインインそのものなので、手元のセッションは付けない。
                val response = http.request(
                    "POST", "/auth/login", JSONObject().put("google_id_token", googleIdToken), authorized = false
                )
                val code = response.code
                val text = response.body
                if (!response.isSuccess || text.isNullOrEmpty()) {
                    Log.w(TAG, "auth/login -> HTTP $code body=$text")
                    return@withContext Result.failure(IllegalStateException("login failed: HTTP $code"))
                }
                val json = JSONObject(text)
                val sessionToken = json.getString("sessionToken")
                val displayName = json.optString("displayName").ifEmpty { null }
                val isAdmin = json.optBoolean("isAdmin", false)
                prefs.edit()
                    .putString(KEY_SESSION_TOKEN, sessionToken)
                    .putString(KEY_DISPLAY_NAME, displayName)
                    .putBoolean(KEY_IS_ADMIN, isAdmin)
                    .apply()
                _state.value = AuthState(
                    isSignedIn = true,
                    displayName = displayName,
                    isAdmin = isAdmin,
                    // `/auth/login` は isBanned を返さない契約なので直近の判明値を引き継ぐ (iOS と同じ)。
                    // signOut で prefs ごと消えるため、別アカウントへ BAN が漏れることはない。
                    isBanned = prefs.getBoolean(KEY_IS_BANNED, false)
                )
                Result.success(Unit)
            } catch (e: Exception) {
                Log.w(TAG, "exchangeForSession failed: ${e.message}")
                Result.failure(e)
            }
        }

    companion object {
        private const val TAG = "AuthService"
        private const val PREFS_NAME = "imas_auth_secure"

        /** コアの復元規則に渡す「サインインしている」印 (Android はユーザー ID を保存していない)。 */
        private const val SIGNED_IN_MARKER = "android-session"

        private fun nowEpochSeconds(): Long = System.currentTimeMillis() / 1000

        private fun openEncryptedPrefs(context: Context): SharedPreferences =
            EncryptedSharedPreferences.create(
                context,
                PREFS_NAME,
                MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )

        /**
         * 読めなくなった保存先を消す。prefs のファイルと、それを暗号化していた鍵
         * (AndroidKeyStore の MasterKey。この鍵を使うのは認証の保存先だけ) の両方。
         * 鍵が無い・キーストアが使えない環境では、鍵の削除は黙って飛ばす。
         */
        private fun resetSecurePrefs(context: Context) {
            context.deleteSharedPreferences(PREFS_NAME)
            runCatching {
                KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                    .deleteEntry(MasterKey.DEFAULT_MASTER_KEY_ALIAS)
            }
        }

        /** 前面に出たときの /auth/me の問い合わせ間隔。BAN は編集 API の 403 でもその場で反映される。 */
        private const val ME_REFRESH_INTERVAL_MS = 6 * 60 * 60 * 1000L
        private const val KEY_SESSION_TOKEN = "session_token"
        private const val KEY_DISPLAY_NAME = "display_name"
        private const val KEY_IS_ADMIN = "is_admin"
        private const val KEY_IS_BANNED = "is_banned"
    }
}
