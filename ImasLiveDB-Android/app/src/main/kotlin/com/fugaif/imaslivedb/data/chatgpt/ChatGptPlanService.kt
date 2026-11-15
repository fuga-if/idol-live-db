package com.fugaif.imaslivedb.data.chatgpt

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.content.edit
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.fugaif.imaslivedb.MainActivity
import java.security.SecureRandom
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import uniffi.imas_core.ChatGptAuthException
import uniffi.imas_core.ChatGptFailure
import uniffi.imas_core.ChatGptModel
import uniffi.imas_core.ChatGptRefreshOutcome
import uniffi.imas_core.ChatGptRegistration
import uniffi.imas_core.ChatGptSignInIntent
import uniffi.imas_core.ChatGptSignInOutcome
import uniffi.imas_core.ChatGptTokens
import uniffi.imas_core.chatgptAttemptRandomBytes
import uniffi.imas_core.chatgptBeginSignIn
import uniffi.imas_core.chatgptCanUsePlan
import uniffi.imas_core.chatgptEndpoints
import uniffi.imas_core.chatgptFinishSignIn
import uniffi.imas_core.chatgptHostId
import uniffi.imas_core.chatgptIsExpectedCallback
import uniffi.imas_core.chatgptNeedsRefresh
import uniffi.imas_core.chatgptReadCallback
import uniffi.imas_core.chatgptReadRefresh
import uniffi.imas_core.chatgptRefreshForm
import uniffi.imas_core.chatgptRevocationEndpoint
import uniffi.imas_core.chatgptRevokeForm
import uniffi.imas_core.chatgptShouldForgetPending
import uniffi.imas_core.chatgptSignInExpiredMessage
import uniffi.imas_core.naturalSearchPickModel

/** セッションの失敗。文言は表示用。 */
class ChatGptSessionException(message: String) : Exception(message) {
    companion object {
        fun notSignedIn() = ChatGptSessionException("ChatGPT にログインしていません")
    }
}

/** 設定とシートが読む状態。 */
data class ChatGptState(
    val registration: ChatGptRegistration? = null,
    val tokens: ChatGptTokens? = null,
    val isSigningIn: Boolean = false,
    /** サインイン中のアカウントで選べるモデル (サーバの並び順)。 */
    val models: List<ChatGptModel> = emptyList(),
    /** 直前のサインインの失敗。出したら [ChatGptPlanService.clearSignInError] で消す。 */
    val signInError: String? = null,
) {
    val isSignedIn: Boolean get() = tokens != null
    val canUsePlan: Boolean get() = tokens?.let { chatgptCanUsePlan(it) } ?: false
}

/**
 * Sign in with ChatGPT のサインイン状態と資格情報。iOS `ChatGPTPlanSession`。
 *
 * 利用者の ChatGPT プラン (Plus / Pro) で推論を回すための口。このアプリのアカウント (Google でサインイン) とは
 * 別物で、ここで得た識別子をサーバへ送ることはない。
 *
 * どの client_id で入るか・認可 URL・callback とトークン応答の読み方・いつ更新するかは全部コア (`chatgpt_plan.rs`)。
 * ここは待ち受けを立て、ブラウザを開き、フォームを POST し、コアが返したものを暗号化した prefs に置くだけ。
 *
 * 保存は暗号化 prefs (この端末のみ・バックアップ対象外)。登録 (発行済み client_id とアカウント) とトークンは分けて持つ:
 * サインアウトではトークンだけ消し、次のサインインで同じ client_id を使い回す (新しいクライアントを作らない)。
 */
class ChatGptPlanService(context: Context) {
    private val appContext = context.applicationContext
    private val prefs: SharedPreferences = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val secure: SharedPreferences? by lazy {
        runCatching {
            EncryptedSharedPreferences.create(
                appContext,
                SECURE_PREFS,
                MasterKey.Builder(appContext).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        }.onFailure { Log.w(TAG, "鍵の保存先を開けない: ${it.message}") }.getOrNull()
    }

    private val _state = MutableStateFlow(
        ChatGptState(
            registration = loadRegistration(),
            tokens = loadTokens(),
        )
    )
    val state: StateFlow<ChatGptState> = _state.asStateFlow()

    private var activeServer: LoopbackCallbackServer? = null

    /** 更新は直列化する (更新用トークンは使い捨て)。 */
    private val refreshLock = Mutex()

    /** 端末ごとに 1 回だけ作って以後ずっと同じ値を送る。 */
    private val hostId: String
        get() {
            secure?.getString(KEY_HOST_ID, null)?.let { return it }
            val created = chatgptHostId(UUID.randomUUID().toString())
            secure?.edit { putString(KEY_HOST_ID, created) }
            return created
        }

    // MARK: - サインイン

    /** 画面より長く生きる (ブラウザへ出ている間に画面が作り直されても、待ち受けと交換は最後まで続ける)。 */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** サインインを始める。結果は [state] に出る (失敗は `signInError`、利用者が止めたときは何も出さない)。 */
    fun startSignIn(context: Context, intent: ChatGptSignInIntent = ChatGptSignInIntent.SIGN_IN) {
        if (_state.value.isSigningIn) return
        _state.update { it.copy(signInError = null) }
        scope.launch {
            try {
                signIn(context, intent)
                runCatching { loadModelsIfNeeded() }
            } catch (_: LoopbackServerException.Cancelled) {
                // 自分でやめた。何も出さない。
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(signInError = e.message ?: "ChatGPT とつなげませんでした") }
            }
        }
    }

    fun clearSignInError() = _state.update { it.copy(signInError = null) }

    /**
     * ブラウザで ChatGPT にログインして許可をもらい、戻りを待って資格情報を受け取る。
     * 利用者が [cancelSignIn] したときは [LoopbackServerException.Cancelled] を投げる。
     */
    private suspend fun signIn(context: Context, intent: ChatGptSignInIntent) {
        if (_state.value.isSigningIn) return
        _state.update { it.copy(isSigningIn = true) }
        var server: LoopbackCallbackServer? = null
        try {
            val registration = _state.value.registration
            val random = ByteArray(chatgptAttemptRandomBytes().toInt()).also { SecureRandom().nextBytes(it) }
            val port = 1455
            val attempt = chatgptBeginSignIn(
                intent = intent,
                registration = registration,
                pendingClientId = secure?.getString(KEY_PENDING_CLIENT_ID, null),
                idToken = _state.value.tokens?.idToken,
                hostId = hostId,
                port = port.toUShort(),
                random = random,
            )
            server = LoopbackCallbackServer(port) { target -> chatgptIsExpectedCallback(target, attempt) }
            activeServer = server
            server.start()

            if (!openBrowser(context, Uri.parse(attempt.authorizeUrl))) {
                throw LoopbackServerException.ListenerFailed("ブラウザを開けませんでした")
            }
            val target = server.waitForCallback()
            bringAppToFront()

            val callback = try {
                chatgptReadCallback(target, attempt)
            } catch (e: ChatGptAuthException) {
                // 途中で残った client_id がもう使えないなら捨てる (次は新規登録からやり直せる)。
                if (chatgptShouldForgetPending(attempt, e is ChatGptAuthException.OAuth)) {
                    secure?.edit { remove(KEY_PENDING_CLIENT_ID) }
                }
                throw e
            }
            if (callback.rememberAsPending) {
                // 交換や検証で落ちても、発行された ID は次の試行で使い回す (連携アプリを増やさない)。
                secure?.edit { putString(KEY_PENDING_CLIENT_ID, callback.clientId) }
            }

            val endpoints = chatgptEndpoints()
            val (status, body) = ChatGptPlanClient.postForm(endpoints.tokenUrl, callback.exchangeForm)
            val outcome = chatgptFinishSignIn(
                attempt = attempt, callback = callback, status = status.toUShort(), body = body,
                registration = registration, nowEpochSeconds = nowEpochSeconds(),
            )
            when (outcome) {
                is ChatGptSignInOutcome.DifferentAccount -> {
                    // 既存の登録は書き換えず、受け取ったばかりのセッションは失効させる。
                    outcome.revokeForm?.let { revoke(it) }
                    throw ChatGptSessionException(outcome.message)
                }
                is ChatGptSignInOutcome.Accepted -> {
                    // 別アカウントに切り替えるなら、前のアカウントのセッションは閉じておく。
                    val old = _state.value.tokens
                    val oldRegistration = registration
                    if (outcome.revokePrevious && old != null && oldRegistration != null) {
                        chatgptRevokeForm(old, oldRegistration)?.let { revoke(it) }
                    }
                    save(outcome.registration)
                    save(outcome.tokens)
                    _state.update { it.copy(models = emptyList()) }
                    secure?.edit { remove(KEY_PENDING_CLIENT_ID) }
                }
            }
        } finally {
            server?.stop()
            activeServer = null
            _state.update { it.copy(isSigningIn = false) }
        }
    }

    fun cancelSignIn() {
        activeServer?.stop()
    }

    /** 認可ページをアプリ内ブラウザ (Custom Tabs) で開く。開けなければ ACTION_VIEW。 */
    private fun openBrowser(context: Context, url: Uri): Boolean {
        val viaTab = runCatching {
            val tab = CustomTabsIntent.Builder().setShowTitle(true).build()
            if (context !is android.app.Activity) tab.intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            tab.launchUrl(context, url)
        }.isSuccess
        if (viaTab) return true
        return runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }.isSuccess
    }

    /** callback を受けたら、ブラウザの上からアプリを前面に戻す。 */
    private fun bringAppToFront() {
        runCatching {
            appContext.startActivity(
                Intent(appContext, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            )
        }.onFailure { Log.w(TAG, "アプリを前面に戻せない: ${it.message}") }
    }

    // MARK: - トークン

    /** 期限が近ければ更新してから返す (いつ更新するかはコア)。 */
    suspend fun validAccessToken(): String {
        val tokens = _state.value.tokens ?: throw ChatGptSessionException.notSignedIn()
        if (!chatgptNeedsRefresh(tokens, nowEpochSeconds())) return tokens.accessToken
        return refresh().accessToken
    }

    suspend fun refresh(): ChatGptTokens {
        val seen = _state.value.tokens ?: throw ChatGptSessionException.notSignedIn()
        return refreshLock.withLock {
            val current = _state.value.tokens ?: throw ChatGptSessionException.notSignedIn()
            // 待っている間に別の呼び出しが更新していたら、それを使う (更新用トークンは使い捨て)。
            if (current.accessToken != seen.accessToken) return@withLock current
            val registration = _state.value.registration ?: throw ChatGptSessionException.notSignedIn()
            val form = chatgptRefreshForm(current, registration) ?: run {
                // 更新用トークンが無い。残すと「連携中」のまま使えないので、消してログインし直してもらう。
                clearTokens()
                throw ChatGptSessionException(chatgptSignInExpiredMessage())
            }
            val (status, body) = ChatGptPlanClient.postForm(chatgptEndpoints().tokenUrl, form)
            // 待っている間にサインアウトや別のサインインが入ったら、古いものを書き戻さない。
            if (_state.value.tokens?.refreshToken != current.refreshToken) throw ChatGptSessionException.notSignedIn()
            when (val outcome = chatgptReadRefresh(status.toUShort(), body, current, nowEpochSeconds())) {
                is ChatGptRefreshOutcome.Renewed -> {
                    save(outcome.tokens)
                    outcome.tokens
                }
                is ChatGptRefreshOutcome.SignInAgain -> {
                    // 使えない更新用トークンは消して、同じ client_id でログインし直してもらう。
                    clearTokens()
                    throw ChatGptSessionException(outcome.message)
                }
                is ChatGptRefreshOutcome.Failed -> throw ChatGptSessionException(outcome.message)
            }
        }
    }

    // MARK: - モデル

    suspend fun loadModelsIfNeeded() {
        val s = _state.value
        if (s.models.isNotEmpty() || !s.canUsePlan) return
        val models = try {
            ChatGptPlanClient.listModels(validAccessToken())
        } catch (e: ChatGptFailureException) {
            settle(e.failure)
            throw e
        }
        _state.update { it.copy(models = models) }
    }

    /** 利用者が選んだモデル。選んでいなければ null。 */
    var savedModel: String?
        get() = prefs.getString(KEY_MODEL, null)
        set(value) = prefs.edit { if (value == null) remove(KEY_MODEL) else putString(KEY_MODEL, value) }

    /** 推論に使うモデル。どれにするか (選んだものが一覧に残っているか・無ければどれか) はコア。 */
    suspend fun resolvedModel(): String {
        loadModelsIfNeeded()
        return naturalSearchPickModel(_state.value.models.map { it.slug }, savedModel)
            ?: throw ChatGptSessionException("この ChatGPT アカウントで使えるモデルがありません")
    }

    // MARK: - サインアウト

    /**
     * 失効を試してからローカルのトークンを消す。登録 (client_id / アカウント) は残す。
     * @return リモートの失効を確認できたか。
     */
    suspend fun signOut(): Boolean {
        // 更新中なら差し替わった後の更新用トークンを失効させる。
        refreshLock.withLock { }
        var revoked = false
        val tokens = _state.value.tokens
        val registration = _state.value.registration
        if (tokens != null && registration != null) {
            chatgptRevokeForm(tokens, registration)?.let { revoked = revoke(it) }
        }
        clearTokens()
        return revoked
    }

    /**
     * 失敗を受けた後始末。「ログインし直し」の失敗 (コアの判断) ならトークンを消す
     * (残すと画面は「連携中」のまま、探すたびに同じ失敗になる)。モデル一覧と推論の両方から呼ぶ。
     */
    fun settle(failure: ChatGptFailure) {
        if (failure.signInAgain) clearTokens()
    }

    /** 失効エンドポイント (discovery から引く。採ってよいかはコア) へ POST する。空の 200 が成功。 */
    private suspend fun revoke(form: String): Boolean = runCatching {
        val discovery = ChatGptPlanClient.get(chatgptEndpoints().discoveryUrl)
        val endpoint = chatgptRevocationEndpoint(discovery) ?: return@runCatching false
        ChatGptPlanClient.postForm(endpoint, form).first == 200
    }.getOrDefault(false)

    // MARK: - 保存

    private fun save(registration: ChatGptRegistration) {
        _state.update { it.copy(registration = registration) }
        secure?.edit {
            putString(
                KEY_REGISTRATION,
                JSONObject()
                    .put("clientID", registration.clientId)
                    .put("subject", registration.subject)
                    .put("email", registration.email ?: JSONObject.NULL)
                    .toString()
            )
        }
    }

    private fun save(tokens: ChatGptTokens) {
        _state.update { it.copy(tokens = tokens) }
        secure?.edit {
            putString(
                KEY_TOKENS,
                JSONObject()
                    .put("accessToken", tokens.accessToken)
                    .put("refreshToken", tokens.refreshToken ?: JSONObject.NULL)
                    .put("idToken", tokens.idToken ?: JSONObject.NULL)
                    .put("scopes", JSONArray(tokens.scopes))
                    .put("expiresAt", tokens.expiresAt)
                    .toString()
            )
        }
    }

    private fun clearTokens() {
        _state.update { it.copy(tokens = null, models = emptyList()) }
        secure?.edit { remove(KEY_TOKENS) }
    }

    private fun loadRegistration(): ChatGptRegistration? = runCatching {
        val json = JSONObject(secure?.getString(KEY_REGISTRATION, null) ?: return null)
        ChatGptRegistration(
            clientId = json.getString("clientID"),
            subject = json.getString("subject"),
            email = json.optString("email").takeIf { !json.isNull("email") && it.isNotEmpty() },
        )
    }.getOrNull()

    private fun loadTokens(): ChatGptTokens? = runCatching {
        val json = JSONObject(secure?.getString(KEY_TOKENS, null) ?: return null)
        val scopes = json.getJSONArray("scopes").let { a -> List(a.length()) { a.getString(it) } }
        ChatGptTokens(
            accessToken = json.getString("accessToken"),
            refreshToken = if (json.isNull("refreshToken")) null else json.getString("refreshToken"),
            idToken = if (json.isNull("idToken")) null else json.getString("idToken"),
            scopes = scopes,
            expiresAt = json.getLong("expiresAt"),
        )
    }.getOrNull()

    private fun nowEpochSeconds(): Long = System.currentTimeMillis() / 1000

    private companion object {
        const val TAG = "ChatGptPlan"
        const val PREFS = "chatgpt_plan"
        const val SECURE_PREFS = "imas_chatgpt_secure"
        const val KEY_HOST_ID = "chatgpt_plan.host_id"
        const val KEY_REGISTRATION = "chatgpt_plan.registration.v2"
        const val KEY_TOKENS = "chatgpt_plan.tokens.v2"
        const val KEY_PENDING_CLIENT_ID = "chatgpt_plan.pending_client_id"
        const val KEY_MODEL = "chatgpt_plan.model"
    }
}
