package com.fugaif.imaslivedb.data.auth

import android.content.Context
import android.util.Log
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.fugaif.imaslivedb.data.community.DeviceIdentity
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

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
class AuthService(private val appContext: Context) {

    // Android の Credential Manager (GetGoogleIdOption) は serverClientId に渡した
    // Web アプリケーション用クライアント ID を id トークンの aud に埋め込む仕様。
    // サーバの GOOGLE_WEB_CLIENT_ID と一致させること。
    private val webClientId =
        "612236234738-q1ku8tnnf4ce9jm1q006jp45k6mmmluc.apps.googleusercontent.com"

    private val masterKey = MasterKey.Builder(appContext)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        appContext,
        "imas_auth_secure",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    val sessionToken: String? get() = prefs.getString(KEY_SESSION_TOKEN, null)

    private val _state = MutableStateFlow(
        AuthState(
            isSignedIn = sessionToken != null,
            displayName = prefs.getString(KEY_DISPLAY_NAME, null),
            isAdmin = prefs.getBoolean(KEY_IS_ADMIN, false),
            // 起動直後 (refreshMe が返る前) にも編集導線を畳めるよう、前回判明した BAN を復元する。
            isBanned = prefs.getBoolean(KEY_IS_BANNED, false)
        )
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
        prefs.edit().clear().apply()
        _state.value = AuthState()
    }

    /**
     * `GET /auth/me` で isAdmin / isBanned / displayName を最新化する。
     * iOS `AuthService.refreshMe` と同じ契約 (レスポンスは素の camelCase)。
     *
     * BAN はサーバ側でしか立たず `/auth/login` は isBanned を返さないので、
     * この再取得が無いと BAN 済みユーザーに編集導線が出続ける。
     * 呼ぶのは起動時 ([com.fugaif.imaslivedb.ImasLiveDBApplication])。iOS も同じタイミング。
     */
    suspend fun refreshMe(): Unit = withContext(Dispatchers.IO) {
        val token = sessionToken ?: return@withContext
        val conn = (URL("$BASE/auth/me").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("X-Device-Id", DeviceIdentity.get(appContext))
            setRequestProperty("Authorization", "Bearer $token")
        }
        try {
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use { it.readText() }
            if (code !in 200..299 || text.isNullOrEmpty()) {
                // 401 でもサインアウトはしない。Android にはセッション再発行 (`/auth/refresh`) の
                // 経路が無く、通信不調と失効を区別できないため、ここで導線を壊すと復帰できなくなる。
                // 失効は編集 API 側の 401 がログイン誘導として拾う。
                Log.w(TAG, "auth/me -> HTTP $code body=$text")
                return@withContext
            }
            val json = JSONObject(text)
            val isAdmin = json.optBoolean("isAdmin", false)
            val isBanned = json.optBoolean("isBanned", false)
            // JSON null は optString が "null" 文字列で返すので isNull で先に弾く。
            val displayName =
                if (json.isNull("displayName")) null else json.optString("displayName").ifEmpty { null }
            val editor = prefs.edit()
                .putBoolean(KEY_IS_ADMIN, isAdmin)
                .putBoolean(KEY_IS_BANNED, isBanned)
            if (displayName != null) editor.putString(KEY_DISPLAY_NAME, displayName)
            editor.apply()
            _state.value = _state.value.copy(
                isAdmin = isAdmin,
                isBanned = isBanned,
                displayName = displayName ?: _state.value.displayName
            )
        } catch (e: Exception) {
            Log.w(TAG, "refreshMe failed: ${e.message}")
        } finally {
            conn.disconnect()
        }
    }

    /**
     * 編集系 API が 403 を返した時に呼ぶ (= BAN の可能性が高い)。
     * 次回起動の [refreshMe] を待たずローカルへ反映し、その場で編集導線を畳む。
     * iOS `AuthService.markBannedFromServer` と同じ best-effort 反映。
     */
    fun markBannedFromServer() {
        prefs.edit().putBoolean(KEY_IS_BANNED, true).apply()
        _state.value = _state.value.copy(isBanned = true)
    }

    /** 表示名を変更する (`POST /users/me`)。iOS `AuthService.updateDisplayName` と同じ契約。 */
    suspend fun updateDisplayName(name: String): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val body = JSONObject().put("display_name", name)
            requestVoid("POST", "/users/me", body)
            prefs.edit().putString(KEY_DISPLAY_NAME, name).apply()
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
        val conn = (URL(BASE + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("X-Device-Id", DeviceIdentity.get(appContext))
            sessionToken?.let { setRequestProperty("Authorization", "Bearer $it") }
        }
        try {
            if (body != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            if (code !in 200..299) {
                val text = conn.errorStream?.bufferedReader()?.use { it.readText() }
                Log.w(TAG, "$method $path -> HTTP $code body=$text")
                throw IllegalStateException("HTTP $code")
            }
        } finally {
            conn.disconnect()
        }
    }

    private suspend fun exchangeForSession(googleIdToken: String): Result<Unit> =
        withContext(Dispatchers.IO) {
            try {
                val url = URL("$BASE/auth/login")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("X-Device-Id", DeviceIdentity.get(appContext))
                }
                val body = JSONObject().put("google_id_token", googleIdToken)
                conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                val code = conn.responseCode
                val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                    ?.bufferedReader()?.use { it.readText() }
                conn.disconnect()
                if (code !in 200..299 || text.isNullOrEmpty()) {
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
        private const val BASE = "https://imas-live-api.tokata3011.workers.dev"
        private const val KEY_SESSION_TOKEN = "session_token"
        private const val KEY_DISPLAY_NAME = "display_name"
        private const val KEY_IS_ADMIN = "is_admin"
        private const val KEY_IS_BANNED = "is_banned"
    }
}
