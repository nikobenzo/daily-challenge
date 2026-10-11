package app.dailychallenge.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * The public client configuration bundled at build time from `.env.local`: only the project
 * URL and the publishable key, never a secret. A placeholder or non-HTTPS URL is refused.
 */
data class SupabaseConfiguration(val url: HttpUrl, val publishableKey: String) {
    companion object {
        fun from(url: String, publishableKey: String): SupabaseConfiguration? {
            val parsed = url.trim().toHttpUrlOrNull() ?: return null
            if (!parsed.isHttps || !publishableKey.startsWith("sb_publishable_") || "your-project" in parsed.host) return null
            return SupabaseConfiguration(parsed, publishableKey.trim())
        }
    }
}

/** A Supabase Auth refusal, with its stable `error_code` when the server sent one. */
class AuthApiException(val status: Int, val code: String?, message: String, val weakPassword: Boolean = false) : Exception(message)

/** A PostgREST refusal (`PGRST204`, `42703`, `54000` and so on). */
class PostgrestException(val status: Int, val code: String?, message: String) : Exception(message)

/** The signed-in session. Only these tokens are stored, never a password. */
data class AuthSession(
    val accessToken: String,
    val refreshToken: String,
    /** Unix seconds. */
    val expiresAt: Long,
    val userID: UUID,
    val email: String?,
) {
    fun encoded(): String = Wire.text(JsonObject(linkedMapOf(
        "access_token" to JsonPrimitive(accessToken), "refresh_token" to JsonPrimitive(refreshToken),
        "expires_at" to JsonPrimitive(expiresAt), "user_id" to JsonPrimitive(userID.toString()),
        "email" to (email?.let(::JsonPrimitive) ?: JsonNull),
    )))

    override fun toString() = "AuthSession(user=$userID, expiresAt=$expiresAt)"

    companion object {
        fun decode(text: String): AuthSession? = try {
            val values = Wire.json.parseToJsonElement(text).jsonObject
            AuthSession(Wire.stringOf(values["access_token"], "access"), Wire.stringOf(values["refresh_token"], "refresh"),
                Wire.longOf(values["expires_at"], "expires"), UUID.fromString(Wire.stringOf(values["user_id"], "user")),
                values["email"]?.jsonPrimitive?.contentOrNull)
        } catch (_: Exception) {
            null
        }

        /** A token response: `access_token`, `refresh_token`, `expires_at` or `expires_in`, `user`. */
        fun fromTokenResponse(values: JsonObject, now: Long): AuthSession? {
            val access = values["access_token"]?.jsonPrimitive?.contentOrNull ?: return null
            val refresh = values["refresh_token"]?.jsonPrimitive?.contentOrNull ?: return null
            val user = values["user"] as? JsonObject ?: return null
            val expiresAt = values["expires_at"]?.jsonPrimitive?.contentOrNull?.toLongOrNull()
                ?: values["expires_in"]?.jsonPrimitive?.contentOrNull?.toLongOrNull()?.let { now + it } ?: (now + 3_600)
            val id = user["id"]?.jsonPrimitive?.contentOrNull?.let(Wire::parseUUID) ?: return null
            return AuthSession(access, refresh, expiresAt, id, user["email"]?.jsonPrimitive?.contentOrNull)
        }
    }
}

/** Where the session is kept: Android Keystore-encrypted storage in the app, memory in tests. */
interface SessionStore {
    fun load(): String?
    fun save(value: String?)
}

class MemorySessionStore(private var value: String? = null) : SessionStore {
    override fun load() = value
    override fun save(value: String?) { this.value = value }
}

/** Minimal HTTPS calls to one Supabase project with the publishable key. Never logs bodies. */
class SupabaseHttp(val configuration: SupabaseConfiguration, private val client: OkHttpClient = defaultClient()) {
    data class Response(val status: Int, val body: String, val headers: okhttp3.Headers)

    suspend fun send(
        method: String,
        path: String,
        query: List<Pair<String, String>> = emptyList(),
        body: JsonElement? = null,
        bearer: String? = null,
        prefer: String? = null,
    ): Response = withContext(Dispatchers.IO) {
        val url = configuration.url.newBuilder().apply {
            path.trim('/').split('/').forEach { addPathSegment(it) }
            // Only the app's own filter values go here (no user input), written as PostgREST expects them.
            query.forEach { (name, value) -> addEncodedQueryParameter(name, value) }
        }.build()
        val request = Request.Builder().url(url)
            .header("apikey", configuration.publishableKey)
            .header("Authorization", "Bearer ${bearer ?: configuration.publishableKey}")
            .header("Accept", "application/json")
            .apply { prefer?.let { header("Prefer", it) } }
            .method(method, body?.let { Wire.text(it).toRequestBody(jsonType) }
                ?: if (method == "POST" || method == "PUT") "".toRequestBody(jsonType) else null)
            .build()
        try {
            client.newCall(request).execute().use { Response(it.code, it.body?.string() ?: "", it.headers) }
        } catch (error: IOException) {
            throw NetworkException(error)
        }
    }

    companion object {
        private val jsonType = "application/json".toMediaType()

        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS).writeTimeout(30, TimeUnit.SECONDS)
            .build()

        fun parse(body: String): JsonElement? = try {
            if (body.isBlank()) null else Wire.json.parseToJsonElement(body)
        } catch (_: Exception) {
            null
        }
    }
}

enum class OtpType(val wire: String) { SIGNUP("signup"), RECOVERY("recovery") }

data class SignUpResult(val session: AuthSession?, val alreadyRegistered: Boolean)

/** What the auth screens need from the server: Supabase Auth in the app, a fake in tests and fixtures. */
interface AuthBackend {
    val session: AuthSession?
    fun onSessionChange(listener: (AuthSession?) -> Unit)
    /** Signs in and keeps the session. */
    suspend fun signIn(email: String, password: String): AuthSession
    /** Keeps the session when the server returns one (email confirmation off). */
    suspend fun signUp(email: String, password: String): SignUpResult
    /** Verifies a code; the session is returned, not kept, until [adopt]. */
    suspend fun verifyOtp(email: String, token: String, type: OtpType): AuthSession?
    fun adopt(session: AuthSession)
    suspend fun resetPasswordForEmail(email: String)
    suspend fun resendSignUp(email: String)
    suspend fun updatePassword(password: String, session: AuthSession? = null)
    /** Removes the session on this device first, then asks the server to end it (best effort). */
    suspend fun signOutLocal(session: AuthSession? = null)
}

/**
 * Supabase Auth over its REST API: password sign-in, sign-up and codes, recovery, password
 * change, local sign-out and token refresh. The session is written to [store] and refreshed
 * shortly before it expires; a refresh the server refuses signs this device out.
 */
class SupabaseAuth(
    private val http: SupabaseHttp,
    private val store: SessionStore,
    private val unixNow: () -> Long = { System.currentTimeMillis() / 1000 },
) : AuthBackend {
    override var session: AuthSession? = store.load()?.let(AuthSession::decode)
        private set
    private val listeners = ArrayList<(AuthSession?) -> Unit>()
    private val refreshLock = Mutex()

    override fun onSessionChange(listener: (AuthSession?) -> Unit) { listeners += listener }

    private fun keep(value: AuthSession?) {
        session = value
        store.save(value?.encoded())
        listeners.forEach { it(value) }
    }

    override fun adopt(session: AuthSession) = keep(session)

    private suspend fun call(method: String, path: String, body: JsonObject? = null, query: List<Pair<String, String>> = emptyList(),
                             bearer: String? = null): JsonElement? {
        val response = http.send(method, "auth/v1/$path", query, body, bearer)
        val parsed = SupabaseHttp.parse(response.body)
        if (response.status !in 200..299) throw authError(response.status, parsed)
        return parsed
    }

    private fun tokenSession(values: JsonElement?): AuthSession =
        (values as? JsonObject)?.let { AuthSession.fromTokenResponse(it, unixNow()) }
            ?: throw AuthApiException(500, null, "The server's answer could not be read.")

    override suspend fun signIn(email: String, password: String): AuthSession {
        val session = tokenSession(call("POST", "token", body(email, password), listOf("grant_type" to "password")))
        keep(session)
        return session
    }

    override suspend fun signUp(email: String, password: String): SignUpResult {
        val values = call("POST", "signup", body(email, password)) as? JsonObject
            ?: throw AuthApiException(500, null, "The server's answer could not be read.")
        AuthSession.fromTokenResponse(values, unixNow())?.let { keep(it); return SignUpResult(it, false) }
        // An already-confirmed address gets an obfuscated user with no identities, so the
        // server does not reveal which addresses exist.
        val user = (values["user"] as? JsonObject) ?: values
        val identities = user["identities"] as? JsonArray
        return SignUpResult(null, identities != null && identities.isEmpty())
    }

    override suspend fun verifyOtp(email: String, token: String, type: OtpType): AuthSession? {
        val values = call("POST", "verify", JsonObject(linkedMapOf(
            "email" to JsonPrimitive(email), "token" to JsonPrimitive(token), "type" to JsonPrimitive(type.wire))))
        return (values as? JsonObject)?.let { AuthSession.fromTokenResponse(it, unixNow()) }
    }

    override suspend fun resetPasswordForEmail(email: String) {
        call("POST", "recover", JsonObject(mapOf("email" to JsonPrimitive(email))))
    }

    override suspend fun resendSignUp(email: String) {
        call("POST", "resend", JsonObject(linkedMapOf("type" to JsonPrimitive("signup"), "email" to JsonPrimitive(email))))
    }

    override suspend fun updatePassword(password: String, session: AuthSession?) {
        val current = session ?: validSession()
        call("PUT", "user", JsonObject(mapOf("password" to JsonPrimitive(password))), bearer = current.accessToken)
    }

    override suspend fun signOutLocal(session: AuthSession?) {
        val ending = session ?: this.session ?: return
        if (session == null || session == this.session) keep(null)
        try {
            call("POST", "logout", query = listOf("scope" to "local"), bearer = ending.accessToken)
        } catch (_: Exception) {
            // The session is already gone here; an expired or unreachable one needs nothing more.
        }
    }

    /** The current session, refreshed first when it expires within a minute. */
    suspend fun validSession(): AuthSession = refreshLock.withLock {
        val current = session ?: throw AuthApiException(401, "session_not_found", "Sign in again to sync.")
        if (current.expiresAt - unixNow() > 60) return current
        try {
            val refreshed = tokenSession(call("POST", "token", JsonObject(mapOf("refresh_token" to JsonPrimitive(current.refreshToken))),
                listOf("grant_type" to "refresh_token")))
            if (session == current) keep(refreshed)
            refreshed
        } catch (error: AuthApiException) {
            // A refused refresh (revoked, signed out elsewhere, deleted account) ends the session here.
            if (error.status in 400..499 && error.status != 429 && session == current) keep(null)
            throw error
        }
    }

    private fun body(email: String, password: String) =
        JsonObject(linkedMapOf("email" to JsonPrimitive(email), "password" to JsonPrimitive(password)))

    companion object {
        fun authError(status: Int, body: JsonElement?): AuthApiException {
            val values = body as? JsonObject
            fun text(key: String) = (values?.get(key) as? JsonPrimitive)?.takeIf { it.isString }?.content
            val code = text("error_code") ?: text("error")?.takeIf { it != "invalid_grant" }
                ?: if (text("error") == "invalid_grant") "invalid_credentials" else null
            val message = text("msg") ?: text("message") ?: text("error_description") ?: "The server refused the request ($status)."
            return AuthApiException(status, code, message, weakPassword = values?.get("weak_password") != null || code == "weak_password")
        }
    }
}

/**
 * The challenge tables over PostgREST (Swift `SupabaseChallengeTransport`): immutable
 * insert-ignore batches and owner-scoped paginated reads. Each request first checks the
 * session still belongs to the account being synced.
 */
class SupabaseChallengeTransport(private val http: SupabaseHttp, private val auth: SupabaseAuth) : ChallengeTransport {
    private suspend fun validate(ownerID: UUID): AuthSession {
        val session = auth.validSession()
        if (session.userID != ownerID) throw ChallengeSyncException(ChallengeSyncError.WRONG_OWNER)
        return session
    }

    private suspend fun rest(method: String, table: String, session: AuthSession, query: List<Pair<String, String>> = emptyList(),
                             body: JsonElement? = null, prefer: String? = null): JsonElement? {
        val response = http.send(method, "rest/v1/$table", query, body, session.accessToken, prefer)
        val parsed = SupabaseHttp.parse(response.body)
        if (response.status !in 200..299) throw postgrestError(response.status, parsed)
        return parsed
    }

    override suspend fun fetchChallenge(ownerID: UUID): ChallengeRecord? {
        val session = validate(ownerID)
        // "*" rather than a column list: a server without the timezone migration returns no
        // time_zone, which reads as Jersey instead of failing.
        val rows = rest("GET", "challenges", session, listOf("select" to "*", "owner_id" to "eq.${Challenge.uuidString(ownerID)}"))
            as? JsonArray ?: throw ChallengeSyncException(ChallengeSyncError.INVALID_RECORD)
        if (rows.size > 1) throw ChallengeSyncException(ChallengeSyncError.CONFLICTING_CHALLENGE)
        return rows.firstOrNull()?.let {
            try {
                Wire.decodeRecord(it)
            } catch (_: WireException) {
                throw ChallengeSyncException(ChallengeSyncError.INVALID_RECORD)
            }
        }
    }

    override suspend fun insertChallenge(record: ChallengeRecord) {
        val session = validate(record.ownerID)
        try {
            rest("POST", "challenges", session, listOf("on_conflict" to "owner_id"), Wire.encode(record), IGNORE_DUPLICATES)
        } catch (error: PostgrestException) {
            // PGRST204 (PostgREST) or 42703 (PostgreSQL): the timezone migration is missing.
            if (error.code in setOf("PGRST204", "42703") && "time_zone" in (error.message ?: "")) {
                throw ChallengeSyncException(ChallengeSyncError.SERVER_NEEDS_TIME_ZONE_UPDATE)
            }
            throw error
        }
    }

    override suspend fun upload(events: List<ChallengeEvent>, ownerID: UUID) {
        if (!events.all { it.ownerID == ownerID && it.receivedAt == null }) throw ChallengeSyncException(ChallengeSyncError.WRONG_OWNER)
        // Parent pours must exist before any batch containing their undo.
        val ordered = events.filter { it.activity.undonePourID == null } + events.filter { it.activity.undonePourID != null }
        for (batch in ordered.chunked(200)) {
            val session = validate(ownerID)
            rest("POST", "challenge_events", session, listOf("on_conflict" to "owner_id,id"),
                JsonArray(batch.map(Wire::encode)), IGNORE_DUPLICATES)
        }
    }

    override suspend fun fetchEvents(ownerID: UUID, challengeID: UUID): RemoteEvents {
        val events = ArrayList<ChallengeEvent>()
        var skipped = 0
        var offset = 0
        while (true) {
            val session = validate(ownerID)
            val page = rest("GET", "challenge_events", session, listOf(
                "select" to "id,owner_id,challenge_id,activity,received_at",
                "owner_id" to "eq.${Challenge.uuidString(ownerID)}", "challenge_id" to "eq.${Challenge.uuidString(challengeID)}",
                "order" to "id.asc", "offset" to "$offset", "limit" to "$PAGE",
            )) as? JsonArray ?: throw ChallengeSyncException(ChallengeSyncError.INVALID_RECORD)
            // A row this app can't read (written by a newer client) is skipped, not fatal.
            for (row in page) {
                try {
                    events += Wire.decodeEvent(row)
                } catch (_: WireException) {
                    skipped++
                }
            }
            // Pages count server rows, so a skipped row never ends paging early.
            if (page.size < PAGE) return RemoteEvents(events, skipped)
            offset += page.size
        }
    }

    companion object {
        const val PAGE = 500
        const val IGNORE_DUPLICATES = "resolution=ignore-duplicates,return=minimal"

        fun postgrestError(status: Int, body: JsonElement?): PostgrestException {
            val values = body as? JsonObject
            fun text(key: String) = (values?.get(key) as? JsonPrimitive)?.takeIf { it.isString }?.content
            val message = text("message") ?: "The server refused the request ($status)."
            val friendly = if (text("code") == "54000") "This account has reached its entry limit on the server. Nothing was lost on this phone." else message
            return PostgrestException(status, text("code"), friendly)
        }
    }
}

enum class AccountDeletionError(val message: String) {
    SERVER_NEEDS_UPDATE("The server needs the account deletion update first."),
    WRONG_ACCOUNT("The signed-in account changed. Open Account again and retry."),
}

class AccountDeletionException(val error: AccountDeletionError) : Exception(error.message)

/** Deletes the signed-in account on the server. Repeating it for a deleted account also succeeds. */
interface AccountDeletionTransport {
    suspend fun deleteAccount(ownerID: UUID)
}

/**
 * Calls `delete_own_account()` with the session's own token and the publishable key; it takes
 * no account argument, so it can only delete the caller (`20261011000100_account_deletion.sql`).
 */
class SupabaseAccountDeletion(private val http: SupabaseHttp, private val auth: SupabaseAuth) : AccountDeletionTransport {
    override suspend fun deleteAccount(ownerID: UUID) {
        val session = auth.validSession()
        if (session.userID != ownerID) throw AccountDeletionException(AccountDeletionError.WRONG_ACCOUNT)
        val response = http.send("POST", "rest/v1/rpc/delete_own_account", body = JsonObject(emptyMap()), bearer = session.accessToken)
        if (response.status in 200..299) return
        val error = SupabaseChallengeTransport.postgrestError(response.status, SupabaseHttp.parse(response.body))
        // PGRST202 (PostgREST) or 42883 (PostgreSQL): the deletion migration is missing.
        if (error.code in setOf("PGRST202", "42883") && "delete_own_account" in (error.message ?: "")) {
            throw AccountDeletionException(AccountDeletionError.SERVER_NEEDS_UPDATE)
        }
        throw error
    }
}
