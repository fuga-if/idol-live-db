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
    val isAdmin: Boolean = false
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
            isAdmin = prefs.getBoolean(KEY_IS_ADMIN, false)
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
                _state.value = AuthState(isSignedIn = true, displayName = displayName, isAdmin = isAdmin)
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
    }
}
