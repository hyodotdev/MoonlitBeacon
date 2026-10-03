package dev.moonlitbeacon.identity

import android.app.Activity
import android.content.pm.PackageManager
import android.util.Log
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.games.PlayGames
import com.google.android.gms.tasks.Task
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.AuthCredential
import com.google.firebase.auth.AuthResult
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.auth.FirebaseAuthRecentLoginRequiredException
import com.google.firebase.auth.FirebaseAuthUserCollisionException
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.auth.OAuthProvider
import com.google.firebase.auth.PlayGamesAuthProvider
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject

/**
 * Native player identity for Android: ordinary Google sign-in through
 * Credential Manager plus Google ID (`google.com`), Apple sign-in through
 * the Firebase `apple.com` browser flow, the optional Play Games Services
 * v2 gaming profile (`playgames.google.com`), and anonymous guests — all
 * exchanged for Firebase credentials.
 *
 * Every method below takes a Godot-issued `requestId` plus one JSON argument
 * object and answers synchronously with a receipt JSON object. A `pending`
 * receipt is always followed by exactly one terminal outcome on the
 * `moonlit_identity_event` signal carrying the same `requestId`.
 *
 * Cancellation boundary: `moonlitCancelRequest` answers `cancelled` while no
 * irreversible SDK mutation began (the credential picker not yet answered,
 * the browser flow not yet started, the Firebase call not yet invoked), or
 * `draining` once a mutation began. Draining keeps the request tracked and
 * the terminal still arrives on the signal. Every stage checks the pending
 * set before invoking the next SDK call, so a cancelled request never
 * starts a mutation it can no longer report.
 *
 * Firebase is initialized from the staged public client config carried in
 * each call's payload (`firebase_api_key`, `firebase_app_id`,
 * `firebase_project_id`, `firebase_sender_id`). When no configured app
 * exists and the values are absent or rejected, calls answer with an
 * explicit `not_configured` outcome instead of throwing.
 *
 * Outcomes carry only identifiers and status (`uid`, `provider`, `kind`).
 * The Google ID token, the Play Games server auth code, and the Apple
 * browser exchange are consumed inside the Firebase calls and never leave
 * this class. The Firebase ID token is returned only as the `id_token`
 * field of a `moonlitGetIdToken` answer. Google's SDK authenticates
 * under its own default account scopes (openid/email/profile): this
 * class adds no scopes of its own and never reads, logs, or stores an
 * email, a display name, a profile, a token, or an auth code —
 * diagnostics name the request id, the status, and the code only.
 */
class MoonlitIdentityPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "MoonlitIdentity"
        private const val SIGNAL_EVENT = "moonlit_identity_event"
        private const val PROVIDER_GOOGLE = "google"
        private const val PROVIDER_PLAY_GAMES = "play_games"
        private const val PROVIDER_APPLE = "apple"
        private const val PROVIDER_ANONYMOUS = "anonymous"

        // Firebase provider ids behind the game-level provider names. The
        // Play Games gaming profile is its own account and is never merged
        // with the ordinary Google account.
        private const val FIREBASE_GOOGLE = "google.com"
        private const val FIREBASE_APPLE = "apple.com"
        private const val FIREBASE_PLAY_GAMES = "playgames.google.com"
        // The Firebase-internal providerData entry every user carries; it
        // names no sign-in method and is skipped when mapping providers.
        private const val FIREBASE_INTERNAL_ENTRY = "firebase"

        private const val STATUS_OK = "ok"
        private const val STATUS_PENDING = "pending"
        private const val STATUS_CANCELLED = "cancelled"
        private const val STATUS_CONFLICT = "conflict"
        private const val STATUS_ERROR = "error"
        private const val STATUS_DRAINING = "draining"
        private const val STATUS_NOT_CONFIGURED = "not_configured"

        private const val CODE_USER_CANCELLED = "user_cancelled"
        private const val CODE_ALREADY_LINKED_ELSEWHERE = "already_linked_elsewhere"
        private const val CODE_MISSING_CONFIG = "identity_not_configured"
        private const val CODE_UNKNOWN_PROVIDER = "unknown_provider"
        private const val CODE_NETWORK = "network_error"
        private const val CODE_RECENT_LOGIN_REQUIRED = "recent_login_required"
        private const val CODE_NO_SIGNED_IN_USER = "no_signed_in_user"
        private const val CODE_NO_GOOGLE_ACCOUNT = "no_google_account"
        private const val CODE_ALREADY_PENDING = "request_already_pending"
        private const val CODE_MUTATION_IN_PROGRESS = "mutation_in_progress"

        private const val PLAY_APP_ID_KEY = "com.google.android.gms.games.APP_ID"

        private const val SETTLED_CAP = 64
    }

    private val auth: FirebaseAuth by lazy { FirebaseAuth.getInstance() }

    /** Request ids with work still in flight. Guarded by [lock]. */
    private val pending = mutableSetOf<String>()

    /**
     * Owner of the single native mutation slot. At most one
     * sign-in/link/delete/sign-out request runs at a time; a second mutating
     * request answers `mutation_in_progress` until the first settles. The
     * slot releases only on SDK completion or pre-mutation cancel — never on
     * a GDScript timeout — so a UI deadline can never start a second
     * mutation that races the first Task's real outcome. Guarded by [lock].
     */
    private var mutationOwner: String? = null

    /** Request ids already settled, oldest first. Guarded by [lock]. */
    private val settledOrder = ArrayDeque<String>()
    private val settled = mutableSetOf<String>()

    /**
     * Requests whose irreversible SDK mutation already began
     * (anonymous/credential sign-in, link, delete). Guarded by [lock].
     */
    private val mutations = mutableSetOf<String>()

    /**
     * Main-thread scope for Credential Manager's suspend calls (the pinned
     * 1.3.0 API is suspend-only: no callback overload exists). The plugin
     * lives for the process lifetime, so the scope is never cancelled; one
     * child job per Google request carries that request's cancellation.
     */
    private val credentialScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * Credential Manager jobs for Google requests still awaiting the
     * account picker. The picker is pre-mutation, so cancel stops the job
     * and drops the request. Guarded by [lock].
     */
    private val credentialJobs = mutableMapOf<String, Job>()

    private val lock = Any()

    override fun getPluginName(): String = "MoonlitIdentity"

    override fun getPluginSignals(): MutableSet<SignalInfo> {
        return mutableSetOf(SignalInfo(SIGNAL_EVENT, String::class.java))
    }

    // ------------------------------------------------------------------
    // Firebase initialization from staged public client config.
    // ------------------------------------------------------------------

    /**
     * Returns true when a Firebase app is usable. Uses the already
     * configured app when one exists (normal export path); otherwise builds
     * one from the staged public values in [args]. Never throws: a missing
     * or rejected config settles the request as `not_configured`.
     */
    private fun ensureFirebase(requestId: String, args: JSONObject): Boolean {
        val host = activity
        if (host == null) {
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            return false
        }
        if (FirebaseApp.getApps(host).isNotEmpty()) return true
        val apiKey = args.optString("firebase_api_key", "").trim()
        val appId = args.optString("firebase_app_id", "").trim()
        val projectId = args.optString("firebase_project_id", "").trim()
        val senderId = args.optString("firebase_sender_id", "").trim()
        if (apiKey.isEmpty() || appId.isEmpty() || projectId.isEmpty()
            || senderId.isEmpty()
        ) {
            finish(requestId, notConfigured(requestId))
            return false
        }
        return try {
            val options = FirebaseOptions.Builder()
                .setApiKey(apiKey)
                .setApplicationId(appId)
                .setProjectId(projectId)
                .setGcmSenderId(senderId)
                .build()
            FirebaseApp.initializeApp(host, options)
            true
        } catch (error: Exception) {
            Log.d(TAG, "firebase-init $requestId rejected: ${error.javaClass.simpleName}")
            finish(requestId, notConfigured(requestId))
            false
        }
    }

    /**
     * Synchronous Firebase init for cold-start session reads. Uses the
     * already configured app when one exists (normal export path);
     * otherwise builds one from the staged public values in [args]. Never
     * touches request bookkeeping and emits no signal: a missing or
     * rejected config answers false so the caller falls through to its
     * guarded local session. Never signs in, never switches users, never
     * logs a value — the rejection names the request id and the exception
     * only.
     */
    private fun ensureSessionApp(requestId: String, args: JSONObject): Boolean {
        val host = activity ?: return false
        if (FirebaseApp.getApps(host).isNotEmpty()) return true
        val apiKey = args.optString("firebase_api_key", "").trim()
        val appId = args.optString("firebase_app_id", "").trim()
        val projectId = args.optString("firebase_project_id", "").trim()
        val senderId = args.optString("firebase_sender_id", "").trim()
        if (apiKey.isEmpty() || appId.isEmpty() || projectId.isEmpty()
            || senderId.isEmpty()
        ) {
            return false
        }
        return try {
            val options = FirebaseOptions.Builder()
                .setApiKey(apiKey)
                .setApplicationId(appId)
                .setProjectId(projectId)
                .setGcmSenderId(senderId)
                .build()
            FirebaseApp.initializeApp(host, options)
            true
        } catch (error: Exception) {
            Log.d(TAG, "firebase-init $requestId rejected: ${error.javaClass.simpleName}")
            false
        }
    }

    // ------------------------------------------------------------------
    // Guest (anonymous Firebase authentication, no Play Games needed).
    // ------------------------------------------------------------------

    @UsedByGodot
    fun moonlitSignInGuest(requestId: String, argsJson: String): String {
        when (beginMutating(requestId)) {
            MutationClaim.DUPLICATE -> return alreadyPending(requestId)
            MutationClaim.BUSY -> return busyReceipt(requestId)
            MutationClaim.CLAIMED -> Unit
        }
        val args = JSONObject(argsJson)
        if (!ensureFirebase(requestId, args)) {
            return terminalReceipt(requestId, STATUS_NOT_CONFIGURED, CODE_MISSING_CONFIG)
        }
        if (!isLive(requestId)) return terminalReceipt(requestId, STATUS_CANCELLED, CODE_USER_CANCELLED)
        markMutation(requestId)
        auth.signInAnonymously()
            .addOnSuccessListener { result ->
                val user = result.user
                if (user == null || user.uid.isEmpty()) {
                    finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
                } else {
                    finish(requestId, cloudSession(requestId, user, PROVIDER_ANONYMOUS))
                }
            }
            .addOnFailureListener { error ->
                Log.d(TAG, "guest $requestId failed: ${error.javaClass.simpleName}")
                finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            }
        return pendingReceipt(requestId)
    }

    // ------------------------------------------------------------------
    // Provider sign-in and link (ordinary Google account: Credential
    // Manager plus Google ID, exchanged for a Firebase `google.com`
    // credential — the same provider iOS signs in with).
    //
    // The picker shows every Google account on the device
    // (`filterByAuthorizedAccounts(false)`) without auto-selecting one, so
    // the player always chooses explicitly. The ID token is consumed
    // inside the Firebase call and never leaves this class.
    // ------------------------------------------------------------------

    private fun beginGoogleFlow(
        requestId: String,
        argsJson: String,
        wantsLink: Boolean
    ): String {
        when (beginMutating(requestId)) {
            MutationClaim.DUPLICATE -> return alreadyPending(requestId)
            MutationClaim.BUSY -> return busyReceipt(requestId)
            MutationClaim.CLAIMED -> Unit
        }
        val args = JSONObject(argsJson)
        if (!ensureFirebase(requestId, args)) {
            return terminalReceipt(requestId, STATUS_NOT_CONFIGURED, CODE_MISSING_CONFIG)
        }
        val clientId = args.optString("server_client_id", "").trim()
        if (clientId.isEmpty()) {
            finish(requestId, notConfigured(requestId))
            return terminalReceipt(requestId, STATUS_NOT_CONFIGURED, CODE_MISSING_CONFIG)
        }
        val host = activity
        if (host == null) {
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            return terminalReceipt(requestId, STATUS_ERROR, CODE_NETWORK)
        }
        if (!isLive(requestId)) return terminalReceipt(requestId, STATUS_CANCELLED, CODE_USER_CANCELLED)
        val option = GetGoogleIdOption.Builder()
            .setFilterByAuthorizedAccounts(false)
            .setServerClientId(clientId)
            .setAutoSelectEnabled(false)
            .build()
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(option)
            .build()
        // Pre-mutation: the picker can still be dismissed by cancel, which
        // reports `cancelled`, not `draining`. The launch returns at once;
        // the suspend call completes later with the credential or an error.
        val manager = CredentialManager.create(host)
        val job = credentialScope.launch {
            requestGoogleCredential(requestId, manager, host, request, wantsLink)
        }
        synchronized(lock) {
            credentialJobs[requestId] = job
        }
        return pendingReceipt(requestId)
    }

    private suspend fun requestGoogleCredential(
        requestId: String,
        manager: CredentialManager,
        host: Activity,
        request: GetCredentialRequest,
        wantsLink: Boolean
    ) {
        try {
            // Suspend-only in the pinned 1.3.0 API: context first, then the
            // request. Dismissal throws GetCredentialCancellationException;
            // a bare device throws NoCredentialException.
            val result = manager.getCredential(host, request)
            onGoogleCredential(requestId, result, wantsLink)
        } catch (error: CancellationException) {
            // Our own cancel stopped this job after dropping the request,
            // so no terminal may follow. Forget the job entry only.
            forgetCredentialJob(requestId)
        } catch (error: GetCredentialException) {
            onGoogleCredentialError(requestId, error)
        } catch (error: Exception) {
            if (!isLive(requestId)) return
            Log.d(TAG, "google-picker $requestId failed: ${error.javaClass.simpleName}")
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
        }
    }

    private fun forgetCredentialJob(requestId: String) {
        synchronized(lock) {
            credentialJobs.remove(requestId)
        }
    }

    private fun onGoogleCredential(
        requestId: String,
        result: GetCredentialResponse,
        wantsLink: Boolean
    ) {
        if (!isLive(requestId)) return
        val credential = result.credential
        if (credential !is CustomCredential ||
            credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            return
        }
        val idToken = try {
            GoogleIdTokenCredential.createFrom(credential.data).idToken
        } catch (error: Exception) {
            Log.d(TAG, "google-token $requestId unreadable: ${error.javaClass.simpleName}")
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            return
        }
        if (idToken.isEmpty()) {
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            return
        }
        completeWithCredential(
            requestId,
            GoogleAuthProvider.getCredential(idToken, null),
            PROVIDER_GOOGLE,
            wantsLink
        )
    }

    private fun onGoogleCredentialError(requestId: String, error: GetCredentialException) {
        if (!isLive(requestId)) return
        when (error) {
            // The player closed the picker: the Firebase user, if any, is
            // untouched, so a cancelled link keeps the guest account.
            is GetCredentialCancellationException -> {
                finish(requestId, cancelled(requestId, CODE_USER_CANCELLED))
            }
            // No Google account on the device can answer this request. Not
            // retryable in place: the player adds an account in system
            // settings, outside the game.
            is NoCredentialException -> {
                finish(requestId, error(requestId, CODE_NO_GOOGLE_ACCOUNT, retryable = false))
            }
            else -> {
                Log.d(TAG, "google-picker $requestId failed: ${error.javaClass.simpleName}")
                finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            }
        }
    }

    // ------------------------------------------------------------------
    // Provider sign-in and link (Apple: Firebase `apple.com` browser flow).
    //
    // The OAuth exchange runs in a provider-hosted browser activity owned
    // by Firebase Auth; this class never sees profile fields, and all
    // Service ID/key material stays in the Firebase console (server-side).
    // `pendingAuthResult` reattaches to a flow that outlived an activity
    // recreation instead of starting a second one. Once the browser intent
    // fires the request is draining: the external flow cannot be recalled,
    // so cancel reports `draining` and the terminal still arrives on the
    // signal.
    // ------------------------------------------------------------------

    private fun beginAppleFlow(
        requestId: String,
        argsJson: String,
        wantsLink: Boolean
    ): String {
        when (beginMutating(requestId)) {
            MutationClaim.DUPLICATE -> return alreadyPending(requestId)
            MutationClaim.BUSY -> return busyReceipt(requestId)
            MutationClaim.CLAIMED -> Unit
        }
        val args = JSONObject(argsJson)
        if (!ensureFirebase(requestId, args)) {
            return terminalReceipt(requestId, STATUS_NOT_CONFIGURED, CODE_MISSING_CONFIG)
        }
        val host = activity
        if (host == null) {
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            return terminalReceipt(requestId, STATUS_ERROR, CODE_NETWORK)
        }
        if (!isLive(requestId)) return terminalReceipt(requestId, STATUS_CANCELLED, CODE_USER_CANCELLED)
        // No custom scopes and no profile reads: whatever consent sheet
        // Apple shows, this class never asks for, reads, logs, or stores
        // a name or email.
        val provider = OAuthProvider.newBuilder(FIREBASE_APPLE).build()
        val resumed = auth.pendingAuthResult
        if (resumed != null) {
            // The browser flow started before an activity recreation: the
            // external exchange is already in flight, so this request is
            // draining from here and the task's terminal still lands.
            markMutation(requestId)
            attachAppleTask(requestId, resumed, PROVIDER_APPLE)
            return pendingReceipt(requestId)
        }
        if (wantsLink && auth.currentUser == null) {
            finish(requestId, error(requestId, CODE_NO_SIGNED_IN_USER, retryable = false))
            return terminalReceipt(requestId, STATUS_ERROR, CODE_NO_SIGNED_IN_USER)
        }
        markMutation(requestId)
        try {
            val task = if (wantsLink) {
                auth.currentUser!!.startActivityForLinkWithProvider(host, provider)
            } else {
                auth.startActivityForSignInWithProvider(host, provider)
            }
            attachAppleTask(requestId, task, PROVIDER_APPLE)
        } catch (error: Exception) {
            Log.d(TAG, "apple-browser $requestId failed: ${error.javaClass.simpleName}")
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            return terminalReceipt(requestId, STATUS_ERROR, CODE_NETWORK)
        }
        return pendingReceipt(requestId)
    }

    private fun attachAppleTask(
        requestId: String,
        task: Task<AuthResult>,
        provider: String
    ) {
        task
            .addOnSuccessListener { result ->
                if (!isLive(requestId)) return@addOnSuccessListener
                val user = result.user
                if (user == null || user.uid.isEmpty()) {
                    finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
                } else {
                    finish(requestId, cloudSession(requestId, user, provider))
                }
            }
            .addOnFailureListener { error ->
                if (!isLive(requestId)) return@addOnFailureListener
                // Closing the browser fails the task without touching the
                // Firebase user, so a cancelled link keeps the guest.
                if (error is FirebaseAuthException &&
                    error.errorCode == "ERROR_WEB_CONTEXT_CANCELLED"
                ) {
                    finish(requestId, cancelled(requestId, CODE_USER_CANCELLED))
                } else {
                    finish(requestId, classifyCredentialError(requestId, error, provider))
                }
            }
    }

    // ------------------------------------------------------------------
    // Provider sign-in and link (Play Games v2 server auth-code flow).
    //
    // v2 has no sign-in intent and no programmatic sign-out. `signIn()`
    // shows the real profile sheet when the player is not signed in and
    // completes silently when they are; dismissal fails the Task. The
    // gaming profile stays optional and distinct: it is never a
    // prerequisite for guest or Google play, and its `playgames.google.com`
    // account is never merged with `google.com`.
    // ------------------------------------------------------------------

    @UsedByGodot
    fun moonlitSignInProvider(requestId: String, argsJson: String): String {
        return beginProviderFlow(requestId, argsJson, wantsLink = false)
    }

    @UsedByGodot
    fun moonlitLinkProvider(requestId: String, argsJson: String): String {
        return beginProviderFlow(requestId, argsJson, wantsLink = true)
    }

    private fun beginProviderFlow(
        requestId: String,
        argsJson: String,
        wantsLink: Boolean
    ): String {
        // The GDScript gate already refused unknown providers and missing
        // config; this dispatch double-checks the name so a misrouted call
        // fails loudly instead of running the wrong SDK flow.
        val provider = try {
            JSONObject(argsJson).optString("provider", "").trim()
        } catch (error: Exception) {
            Log.d(TAG, "provider $requestId args unreadable: ${error.javaClass.simpleName}")
            return JSONObject()
                .put("status", STATUS_ERROR)
                .put("code", CODE_UNKNOWN_PROVIDER)
                .put("request_id", requestId)
                .toString()
        }
        return when (provider) {
            PROVIDER_GOOGLE -> beginGoogleFlow(requestId, argsJson, wantsLink)
            PROVIDER_APPLE -> beginAppleFlow(requestId, argsJson, wantsLink)
            PROVIDER_PLAY_GAMES -> beginPlayFlow(requestId, argsJson, wantsLink)
            else -> {
                Log.d(TAG, "provider $requestId unknown")
                JSONObject()
                    .put("status", STATUS_ERROR)
                    .put("code", CODE_UNKNOWN_PROVIDER)
                    .put("request_id", requestId)
                    .toString()
            }
        }
    }

    private fun beginPlayFlow(requestId: String, argsJson: String, wantsLink: Boolean): String {
        when (beginMutating(requestId)) {
            MutationClaim.DUPLICATE -> return alreadyPending(requestId)
            MutationClaim.BUSY -> return busyReceipt(requestId)
            MutationClaim.CLAIMED -> Unit
        }
        val args = JSONObject(argsJson)
        if (!ensureFirebase(requestId, args)) {
            return terminalReceipt(requestId, STATUS_NOT_CONFIGURED, CODE_MISSING_CONFIG)
        }
        // Play Games identifies the game through the APP_ID metadata the
        // export stamps into the app manifest. Without it the sheet cannot
        // attach to a game, so this refuses loudly instead of failing deep
        // inside the sign-in Task.
        if (!playAppIdPresent()) {
            val outcome = notConfigured(requestId, listOf("play_games_app_id"))
            finish(requestId, outcome)
            return outcome.toString()
        }
        val clientId = args.optString("server_client_id", "").trim()
        if (clientId.isEmpty()) {
            finish(requestId, notConfigured(requestId))
            return terminalReceipt(requestId, STATUS_NOT_CONFIGURED, CODE_MISSING_CONFIG)
        }
        val host = activity
        if (host == null) {
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            return terminalReceipt(requestId, STATUS_ERROR, CODE_NETWORK)
        }
        if (!isLive(requestId)) return terminalReceipt(requestId, STATUS_CANCELLED, CODE_USER_CANCELLED)
        PlayGames.getGamesSignInClient(host).isAuthenticated
            .addOnSuccessListener { result ->
                if (!isLive(requestId)) return@addOnSuccessListener
                if (result.isAuthenticated) {
                    requestServerAuthCode(requestId, clientId, wantsLink)
                } else {
                    playSignIn(requestId, clientId, wantsLink)
                }
            }
            .addOnFailureListener {
                if (!isLive(requestId)) return@addOnFailureListener
                playSignIn(requestId, clientId, wantsLink)
            }
        return pendingReceipt(requestId)
    }

    private fun playSignIn(requestId: String, clientId: String, wantsLink: Boolean) {
        val host = activity
        if (host == null || !isLive(requestId)) return
        PlayGames.getGamesSignInClient(host).signIn()
            .addOnSuccessListener { result ->
                if (!isLive(requestId)) return@addOnSuccessListener
                if (result.isAuthenticated) {
                    requestServerAuthCode(requestId, clientId, wantsLink)
                } else {
                    finish(requestId, cancelled(requestId, CODE_USER_CANCELLED))
                }
            }
            .addOnFailureListener { error ->
                if (!isLive(requestId)) return@addOnFailureListener
                // The player closed the sheet: the Firebase user, if any, is
                // untouched, so a cancelled link keeps the guest account.
                if (isUserCancellation(error)) {
                    finish(requestId, cancelled(requestId, CODE_USER_CANCELLED))
                } else {
                    Log.d(TAG, "play-signin $requestId failed: ${error.javaClass.simpleName}")
                    finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
                }
            }
    }

    private fun playAppIdPresent(): Boolean {
        val host = activity ?: return false
        return try {
            val info = host.packageManager.getApplicationInfo(
                host.packageName, PackageManager.GET_META_DATA
            )
            val raw = info.metaData?.get(PLAY_APP_ID_KEY)?.toString()?.trim().orEmpty()
            raw.isNotEmpty() && raw != "0"
        } catch (error: Exception) {
            Log.d(TAG, "app-id check failed: ${error.javaClass.simpleName}")
            false
        }
    }

    private fun isUserCancellation(error: Exception): Boolean {
        if (error is ApiException) {
            return error.statusCode == CommonStatusCodes.CANCELED
                || error.statusCode == CommonStatusCodes.SIGN_IN_REQUIRED
        }
        return false
    }

    private fun requestServerAuthCode(requestId: String, clientId: String, wantsLink: Boolean) {
        val host = activity
        if (host == null || !isLive(requestId)) return
        PlayGames.getGamesSignInClient(host).requestServerSideAccess(clientId, false)
            .addOnSuccessListener { serverAuthCode ->
                if (!isLive(requestId)) return@addOnSuccessListener
                if (serverAuthCode.isNullOrEmpty()) {
                    finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
                    return@addOnSuccessListener
                }
                exchangeAuthCode(requestId, serverAuthCode, wantsLink)
            }
            .addOnFailureListener { error ->
                if (!isLive(requestId)) return@addOnFailureListener
                Log.d(TAG, "auth-code $requestId failed: ${error.javaClass.simpleName}")
                finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            }
    }

    private fun exchangeAuthCode(requestId: String, serverAuthCode: String, wantsLink: Boolean) {
        if (!isLive(requestId)) return
        completeWithCredential(
            requestId,
            PlayGamesAuthProvider.getCredential(serverAuthCode),
            PROVIDER_PLAY_GAMES,
            wantsLink
        )
    }

    /**
     * Complete a sign-in or link with an IdP credential from any flow. A
     * link keeps the Firebase UID (Firebase links the credential onto the
     * signed-in user); a sign-in takes the credential account's UID. The
     * same collision rule holds for every provider: an account already
     * linked elsewhere surfaces as a conflict and neither account is
     * touched — no overwrite, no merge, no silent switch, and never an
     * automatic link from one social provider onto another.
     */
    private fun completeWithCredential(
        requestId: String,
        credential: AuthCredential,
        provider: String,
        wantsLink: Boolean
    ) {
        if (!isLive(requestId)) return
        if (wantsLink) {
            val user = auth.currentUser
            if (user == null) {
                finish(requestId, error(requestId, CODE_NO_SIGNED_IN_USER, retryable = false))
                return
            }
            markMutation(requestId)
            user.linkWithCredential(credential)
                .addOnSuccessListener { result ->
                    val linked = result.user ?: user
                    finish(requestId, cloudSession(requestId, linked, provider))
                }
                .addOnFailureListener { error ->
                    finish(requestId, classifyCredentialError(requestId, error, provider))
                }
        } else {
            markMutation(requestId)
            auth.signInWithCredential(credential)
                .addOnSuccessListener { result ->
                    val user = result.user
                    if (user == null || user.uid.isEmpty()) {
                        finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
                    } else {
                        finish(requestId, cloudSession(requestId, user, provider))
                    }
                }
                .addOnFailureListener { error ->
                    finish(requestId, classifyCredentialError(requestId, error, provider))
                }
        }
    }

    private fun classifyCredentialError(
        requestId: String,
        error: Exception,
        provider: String
    ): JSONObject {
        // A provider account already linked to a different Firebase user
        // must surface as a conflict the UI resolves. Neither account is
        // touched here: no overwrite, no merge, no silent switch.
        if (error is FirebaseAuthUserCollisionException) {
            Log.d(TAG, "credential $requestId conflict")
            return conflict(requestId, provider)
        }
        Log.d(TAG, "credential $requestId failed: ${error.javaClass.simpleName}")
        return error(requestId, CODE_NETWORK, retryable = true)
    }

    // ------------------------------------------------------------------
    // Session, token, sign-out, deletion, cancel.
    // ------------------------------------------------------------------

    @UsedByGodot
    fun moonlitGetSession(requestId: String, argsJson: String): String {
        // Fully synchronous: reads live state, emits no signal, records no
        // bookkeeping. This is the session truth a force-settled request
        // falls back to, so it must never lie about a mutation it missed.
        // Cold-start: configure the default app from the staged public
        // config before the first session read so a saved Firebase user
        // restores instead of answering local guest. Absent or rejected
        // config falls through to the guarded local session below —
        // FirebaseAuth is never touched without a configured app, and this
        // read never signs in, never switches users, never emits a signal.
        val args = try {
            JSONObject(argsJson)
        } catch (error: Exception) {
            Log.d(TAG, "session $requestId args unreadable: ${error.javaClass.simpleName}")
            JSONObject()
        }
        ensureSessionApp(requestId, args)
        return try {
            describeSession(requestId).toString()
        } catch (error: Exception) {
            Log.d(TAG, "session $requestId unreadable: ${error.javaClass.simpleName}")
            localSession(requestId).toString()
        }
    }

    @UsedByGodot
    fun moonlitGetIdToken(requestId: String, argsJson: String): String {
        if (!begin(requestId)) return alreadyPending(requestId)
        val args = JSONObject(argsJson)
        if (!ensureFirebase(requestId, args)) {
            return terminalReceipt(requestId, STATUS_NOT_CONFIGURED, CODE_MISSING_CONFIG)
        }
        val forceRefresh = args.optBoolean("force_refresh", false)
        val user = auth.currentUser
        if (user == null) {
            finish(requestId, error(requestId, CODE_NO_SIGNED_IN_USER, retryable = false))
            return terminalReceipt(requestId, STATUS_ERROR, CODE_NO_SIGNED_IN_USER)
        }
        if (!isLive(requestId)) return terminalReceipt(requestId, STATUS_CANCELLED, CODE_USER_CANCELLED)
        // Read-only: no session mutation, so cancel stays `cancelled` while
        // the fetch is in flight. The raw token is handed to this call's
        // answer only — never written to disk, never logged, never attached
        // to any signal except this request's own outcome.
        user.getIdToken(forceRefresh)
            .addOnSuccessListener { tokenResult ->
                if (!isLive(requestId)) return@addOnSuccessListener
                val token = tokenResult.token
                if (token.isNullOrEmpty()) {
                    finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
                } else {
                    val answer = JSONObject()
                        .put("status", STATUS_OK)
                        .put("request_id", requestId)
                        .put("id_token", token)
                        .put(
                            "token_expires_at",
                            tokenResult.expirationTimestamp * 1000L
                        )
                    finish(requestId, answer)
                }
            }
            .addOnFailureListener { error ->
                if (!isLive(requestId)) return@addOnFailureListener
                Log.d(TAG, "token $requestId failed: ${error.javaClass.simpleName}")
                finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            }
        return pendingReceipt(requestId)
    }

    @UsedByGodot
    fun moonlitSignOut(requestId: String, argsJson: String): String {
        // Synchronous: Firebase sign-out applies at once. Play Games v2
        // offers no programmatic sign-out; the Play profile stays linked at
        // the OS level and re-authenticates silently on the next signIn(),
        // which is the v2 design (sign-out lives in Play Games settings).
        // Without an initialized Firebase app there is nothing to sign out
        // of, which is the same local session either way. While another
        // mutation drains, sign-out waits: clearing the user under a live
        // sign-in Task would let the Task resurrect a session this call
        // just reported as cleared.
        synchronized(lock) {
            if (mutationOwner != null) return busyReceipt(requestId)
        }
        try {
            auth.signOut()
        } catch (error: Exception) {
            Log.d(TAG, "signout $requestId uninitialized: ${error.javaClass.simpleName}")
        }
        return localSession(requestId).toString()
    }

    @UsedByGodot
    fun moonlitDeleteAccount(requestId: String, argsJson: String): String {
        when (beginMutating(requestId)) {
            MutationClaim.DUPLICATE -> return alreadyPending(requestId)
            MutationClaim.BUSY -> return busyReceipt(requestId)
            MutationClaim.CLAIMED -> Unit
        }
        val args = JSONObject(argsJson)
        if (!ensureFirebase(requestId, args)) {
            return terminalReceipt(requestId, STATUS_NOT_CONFIGURED, CODE_MISSING_CONFIG)
        }
        val user = auth.currentUser
        if (user == null) {
            finish(requestId, error(requestId, CODE_NO_SIGNED_IN_USER, retryable = false))
            return terminalReceipt(requestId, STATUS_ERROR, CODE_NO_SIGNED_IN_USER)
        }
        if (!isLive(requestId)) return terminalReceipt(requestId, STATUS_CANCELLED, CODE_USER_CANCELLED)
        val keepGrant = args.optBoolean("keep_provider_grant", false)
        if (!keepGrant && userHasFirebaseProvider(user, FIREBASE_APPLE)) {
            // Apple-linked delete: re-run the provider browser flow for a
            // fresh session, then delete the Firebase user. The sheet is
            // also the player's explicit confirmation of the delete.
            return beginAppleReauthDelete(requestId, user)
        }
        markMutation(requestId)
        attachDeleteTask(requestId, user)
        return pendingReceipt(requestId)
    }

    private fun beginAppleReauthDelete(requestId: String, user: FirebaseUser): String {
        val host = activity
        if (host == null || !isLive(requestId)) {
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            return terminalReceipt(requestId, STATUS_ERROR, CODE_NETWORK)
        }
        val provider = OAuthProvider.newBuilder(FIREBASE_APPLE).build()
        markMutation(requestId)
        try {
            // A reauth browser flow that outlived an activity recreation
            // resumes through the pending task; otherwise a fresh one
            // starts. Both are Task<AuthResult>, so one helper attaches
            // either.
            val task = auth.pendingAuthResult
                ?: user.startActivityForReauthenticateWithProvider(host, provider)
            attachReauth(requestId, user, task)
        } catch (error: Exception) {
            Log.d(TAG, "reauth $requestId failed: ${error.javaClass.simpleName}")
            finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
            return terminalReceipt(requestId, STATUS_ERROR, CODE_NETWORK)
        }
        return pendingReceipt(requestId)
    }

    private fun attachReauth(
        requestId: String,
        user: FirebaseUser,
        task: Task<AuthResult>
    ) {
        task
            .addOnSuccessListener { onReauthenticated(requestId, user) }
            .addOnFailureListener { error -> onReauthFailed(requestId, error) }
    }

    private fun onReauthenticated(requestId: String, user: FirebaseUser) {
        if (!isLive(requestId)) return
        attachDeleteTask(requestId, auth.currentUser ?: user)
    }

    private fun onReauthFailed(requestId: String, error: Exception) {
        if (!isLive(requestId)) return
        if (error is FirebaseAuthException &&
            error.errorCode == "ERROR_WEB_CONTEXT_CANCELLED"
        ) {
            finish(requestId, cancelled(requestId, CODE_USER_CANCELLED))
            return
        }
        Log.d(TAG, "reauth $requestId failed: ${error.javaClass.simpleName}")
        finish(requestId, error(requestId, CODE_RECENT_LOGIN_REQUIRED, retryable = false))
    }

    private fun attachDeleteTask(requestId: String, user: FirebaseUser) {
        user.delete()
            .addOnSuccessListener {
                finish(requestId, localSession(requestId))
            }
            .addOnFailureListener { error ->
                if (error is FirebaseAuthRecentLoginRequiredException) {
                    // Firebase needs a fresh sign-in before a delete. Say so
                    // explicitly so the UI can re-run the provider flow and
                    // retry the delete.
                    finish(
                        requestId, error(
                            requestId, CODE_RECENT_LOGIN_REQUIRED, retryable = false
                        )
                    )
                } else {
                    Log.d(TAG, "delete $requestId failed: ${error.javaClass.simpleName}")
                    finish(requestId, error(requestId, CODE_NETWORK, retryable = true))
                }
            }
    }

    private fun userHasFirebaseProvider(user: FirebaseUser, providerId: String): Boolean {
        return user.providerData.any { info -> info.providerId == providerId }
    }

    /**
     * Answers `cancelled` while no mutation began (the request is dropped
     * and nothing further is emitted for it), or `draining` once an
     * irreversible SDK mutation began (the request stays tracked and its
     * terminal outcome still arrives on the signal).
     */
    @UsedByGodot
    fun moonlitCancelRequest(requestId: String): String {
        val pickerJob: Job?
        synchronized(lock) {
            if (!pending.contains(requestId)) {
                return cancelledReceipt(requestId).toString()
            }
            if (mutations.contains(requestId)) {
                return JSONObject()
                    .put("status", STATUS_DRAINING)
                    .put("request_id", requestId)
                    .toString()
            }
            // Pre-mutation: stop the Google picker job when one is showing
            // (its CancellationException path forgets the job and emits
            // nothing), then drop the request with nothing further
            // emitted for it.
            pickerJob = credentialJobs.remove(requestId)
            pending.remove(requestId)
            if (mutationOwner == requestId) mutationOwner = null
            rememberSettledLocked(requestId)
        }
        // Outside the lock: cancelling never calls back synchronously.
        pickerJob?.cancel()
        return cancelledReceipt(requestId).toString()
    }

    // ------------------------------------------------------------------
    // Receipts and outcomes. Every payload names status/code/request only,
    // plus uid/provider/kind on a cloud session.
    // ------------------------------------------------------------------

    private fun describeSession(requestId: String): JSONObject {
        // No configured app: never touch FirebaseAuth. Cold-start callers
        // initialize from staged config first; when config is absent this
        // local session is the honest synchronous answer.
        val host = activity
        if (host == null || FirebaseApp.getApps(host).isEmpty()) {
            return localSession(requestId)
        }
        val user = auth.currentUser
        if (user == null || user.uid.isEmpty()) {
            return localSession(requestId)
        }
        return cloudSession(requestId, user, providerOfUser(user))
    }

    /**
     * Map the Firebase user to one game-level provider from its linked
     * provider data — never a constant. A user who explicitly linked more
     * than one social provider reports a deterministic priority
     * (google, apple, play games); each link was its own consented call,
     * and the gaming profile is never reported as the Google account.
     */
    private fun providerOfUser(user: FirebaseUser): String {
        if (user.isAnonymous) return PROVIDER_ANONYMOUS
        var sawGoogle = false
        var sawApple = false
        var sawPlayGames = false
        for (info in user.providerData) {
            when (info.providerId) {
                FIREBASE_GOOGLE -> sawGoogle = true
                FIREBASE_APPLE -> sawApple = true
                FIREBASE_PLAY_GAMES -> sawPlayGames = true
                FIREBASE_INTERNAL_ENTRY -> Unit
            }
        }
        return when {
            sawGoogle -> PROVIDER_GOOGLE
            sawApple -> PROVIDER_APPLE
            sawPlayGames -> PROVIDER_PLAY_GAMES
            // Only reachable for a non-anonymous user with no known linked
            // provider, which this bridge never creates: default to the
            // primary social provider rather than inventing a label.
            else -> PROVIDER_GOOGLE
        }
    }

    private fun cloudSession(requestId: String, user: FirebaseUser, provider: String): JSONObject {
        return JSONObject()
            .put("status", STATUS_OK)
            .put("request_id", requestId)
            .put("kind", "cloud")
            .put("uid", user.uid)
            .put("provider", provider)
    }

    private fun localSession(requestId: String): JSONObject {
        return JSONObject()
            .put("status", STATUS_OK)
            .put("request_id", requestId)
            .put("kind", "local_guest")
            .put("uid", "")
            .put("provider", "")
    }

    private fun pendingReceipt(requestId: String): String {
        return JSONObject()
            .put("status", STATUS_PENDING)
            .put("request_id", requestId)
            .toString()
    }

    private fun terminalReceipt(requestId: String, status: String, code: String): String {
        // For calls that already emitted their outcome: the sync answer names
        // the same terminal status so a caller that ignores signals still
        // sees the truth. The outcome itself went out on the signal first.
        val receipt = JSONObject()
            .put("status", status)
            .put("request_id", requestId)
        if (code.isNotEmpty()) receipt.put("code", code)
        return receipt.toString()
    }

    private fun alreadyPending(requestId: String): String {
        return JSONObject()
            .put("status", STATUS_ERROR)
            .put("code", CODE_ALREADY_PENDING)
            .put("request_id", requestId)
            .toString()
    }

    private fun cancelled(requestId: String, code: String): JSONObject {
        return JSONObject()
            .put("status", STATUS_CANCELLED)
            .put("code", code)
            .put("request_id", requestId)
    }

    private fun cancelledReceipt(requestId: String): JSONObject {
        return cancelled(requestId, CODE_USER_CANCELLED)
    }

    private fun conflict(requestId: String, provider: String): JSONObject {
        return JSONObject()
            .put("status", STATUS_CONFLICT)
            .put("code", CODE_ALREADY_LINKED_ELSEWHERE)
            .put("provider", provider)
            .put("request_id", requestId)
    }

    private fun error(requestId: String, code: String, retryable: Boolean): JSONObject {
        return JSONObject()
            .put("status", STATUS_ERROR)
            .put("code", code)
            .put("retryable", retryable)
            .put("request_id", requestId)
    }

    private fun notConfigured(requestId: String, missing: List<String> = emptyList()): JSONObject {
        val outcome = JSONObject()
            .put("status", STATUS_NOT_CONFIGURED)
            .put("code", CODE_MISSING_CONFIG)
            .put("retryable", false)
            .put("request_id", requestId)
        if (missing.isNotEmpty()) {
            outcome.put("missing", org.json.JSONArray(missing))
        }
        return outcome
    }

    /** Returns false when this id is already in flight or settled. */
    private fun begin(requestId: String): Boolean {
        synchronized(lock) {
            if (pending.contains(requestId) || settled.contains(requestId)) return false
            pending.add(requestId)
            return true
        }
    }

    private enum class MutationClaim { CLAIMED, DUPLICATE, BUSY }

    /**
     * Begin a mutating request and claim the single mutation slot. BUSY
     * means another mutation is still draining its SDK Task: the caller
     * must answer `mutation_in_progress` without touching any SDK state.
     */
    private fun beginMutating(requestId: String): MutationClaim {
        synchronized(lock) {
            if (pending.contains(requestId) || settled.contains(requestId)) {
                return MutationClaim.DUPLICATE
            }
            if (mutationOwner != null) return MutationClaim.BUSY
            pending.add(requestId)
            mutationOwner = requestId
            return MutationClaim.CLAIMED
        }
    }

    private fun releaseMutationOwner(requestId: String) {
        synchronized(lock) {
            if (mutationOwner == requestId) mutationOwner = null
        }
    }

    private fun busyReceipt(requestId: String): String {
        return JSONObject()
            .put("status", STATUS_ERROR)
            .put("code", CODE_MUTATION_IN_PROGRESS)
            .put("retryable", true)
            .put("request_id", requestId)
            .toString()
    }

    private fun isLive(requestId: String): Boolean {
        synchronized(lock) {
            return pending.contains(requestId)
        }
    }

    private fun markMutation(requestId: String) {
        synchronized(lock) {
            mutations.add(requestId)
        }
    }

    private fun rememberSettledLocked(requestId: String) {
        if (settled.contains(requestId)) return
        settled.add(requestId)
        settledOrder.addLast(requestId)
        while (settledOrder.size > SETTLED_CAP) {
            settled.remove(settledOrder.removeFirst())
        }
    }

    /**
     * Emit one terminal outcome for a request still in flight. Late or double
     * completions are dropped. Emission runs on the UI thread; the engine
     * marshals the signal onto the Godot thread from there.
     */
    private fun finish(requestId: String, outcome: JSONObject) {
        synchronized(lock) {
            if (!pending.remove(requestId)) return
            mutations.remove(requestId)
            credentialJobs.remove(requestId)
            if (mutationOwner == requestId) mutationOwner = null
            rememberSettledLocked(requestId)
        }
        val payload = outcome.toString()
        val host = activity
        if (host == null) {
            emitSignal(SIGNAL_EVENT, payload)
            return
        }
        host.runOnUiThread {
            emitSignal(SIGNAL_EVENT, payload)
        }
    }
}
