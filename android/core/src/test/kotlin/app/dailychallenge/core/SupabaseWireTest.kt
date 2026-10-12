package app.dailychallenge.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.time.ZoneId
import java.util.UUID

/**
 * The requests the Android client sends and the answers it understands, against a local
 * HTTP server standing in for Supabase (the Swift tests intercept the SDK the same way).
 */
class SupabaseWireTest {
    private lateinit var server: MockWebServer
    private lateinit var http: SupabaseHttp
    private val owner = UUID.fromString("6F1C2A43-0B55-4B5E-9F3D-2C1A7E9B4D10")
    private val key = "sb_publishable_fixture"
    private var unixNow = 1_791_460_800L

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        // The production check refuses plain HTTP; the local stand-in is built directly.
        http = SupabaseHttp(SupabaseConfiguration(server.url("/"), key))
    }

    @After
    fun tearDown() = server.shutdown()

    private fun session(expiresAt: Long = unixNow + 3_600, user: UUID = owner) =
        AuthSession("access-token", "refresh-token", expiresAt, user, "sam@example.com")

    private fun auth(stored: AuthSession? = session()) = SupabaseAuth(http, MemorySessionStore(stored?.encoded())) { unixNow }

    private fun tokenBody(user: UUID = owner, access: String = "new-access") =
        """{"access_token":"$access","token_type":"bearer","expires_in":3600,"expires_at":${unixNow + 3600},"refresh_token":"new-refresh","user":{"id":"$user","email":"sam@example.com"}}"""

    private fun json(code: Int, body: String) = MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body)

    private fun RecordedRequest.text() = body.readUtf8()

    @Test
    fun configurationAcceptsOnlyHttpsAndPublishableKeys() {
        assertTrue(SupabaseConfiguration.from("https://abc.supabase.co", "sb_publishable_x") != null)
        assertNull(SupabaseConfiguration.from("http://abc.supabase.co", "sb_publishable_x"))
        assertNull(SupabaseConfiguration.from("https://abc.supabase.co", "sb_secret_x"))
        assertNull(SupabaseConfiguration.from("https://your-project.supabase.co", "sb_publishable_replace_me"))
        assertNull(SupabaseConfiguration.from("", ""))
    }

    @Test
    fun signInSendsThePasswordGrantAndKeepsOnlyTokens() = runTest {
        val store = MemorySessionStore()
        val auth = SupabaseAuth(http, store) { unixNow }
        server.enqueue(json(200, tokenBody()))
        val session = auth.signIn("sam@example.com", "correct horse 1")
        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/auth/v1/token?grant_type=password", request.path)
        assertEquals(key, request.getHeader("apikey"))
        assertEquals("{\"email\":\"sam@example.com\",\"password\":\"correct horse 1\"}", request.text())
        assertEquals(owner, session.userID)
        val saved = store.load()!!
        assertFalse(saved.contains("correct horse"))
        assertEquals(session, AuthSession.decode(saved))
        assertFalse(session.toString().contains("access"))
    }

    @Test
    fun authErrorsKeepTheirCodesInEitherServerFormat() = runTest {
        val auth = auth(null)
        server.enqueue(json(400, """{"code":400,"error_code":"email_not_confirmed","msg":"Email not confirmed"}"""))
        server.enqueue(json(400, """{"error":"invalid_grant","error_description":"Invalid login credentials"}"""))
        server.enqueue(json(422, """{"code":422,"error_code":"weak_password","msg":"Password is known to be weak","weak_password":{"reasons":["pwned"]}}"""))
        for (expected in listOf("email_not_confirmed", "invalid_credentials", "weak_password")) {
            try {
                auth.signIn("sam@example.com", "x")
                fail("signed in")
            } catch (error: AuthApiException) {
                assertEquals(expected, error.code)
            }
        }
        assertEquals("Choose a stronger password. Password is known to be weak",
            AuthModel.describe(AuthApiException(422, "weak_password", "Password is known to be weak", true)))
    }

    @Test
    fun signUpTellsAConfirmationStepFromAnExistingAddress() = runTest {
        val auth = auth(null)
        server.enqueue(json(200, """{"id":"$owner","email":"sam@example.com","identities":[{"id":"x"}]}"""))
        server.enqueue(json(200, """{"id":"$owner","email":"","identities":[]}"""))
        assertEquals(SignUpResult(null, false), auth.signUp("sam@example.com", "abcdefghij1"))
        assertEquals("/auth/v1/signup", server.takeRequest().path)
        assertEquals(SignUpResult(null, true), auth.signUp("sam@example.com", "abcdefghij1"))
    }

    @Test
    fun codesRecoveryResendAndPasswordChangeUseTheDocumentedBodies() = runTest {
        val auth = auth()
        server.enqueue(json(200, tokenBody()))
        server.enqueue(json(200, "{}"))
        server.enqueue(json(200, "{}"))
        server.enqueue(json(200, """{"id":"$owner"}"""))
        val verified = auth.verifyOtp("sam@example.com", "12345678", OtpType.RECOVERY)
        assertEquals("{\"email\":\"sam@example.com\",\"token\":\"12345678\",\"type\":\"recovery\"}", server.takeRequest().text())
        assertEquals("access-token", auth.session!!.accessToken) // a verified code is not kept until adopted
        auth.resetPasswordForEmail("sam@example.com")
        server.takeRequest().let { assertEquals("/auth/v1/recover", it.path); assertEquals("{\"email\":\"sam@example.com\"}", it.text()) }
        auth.resendSignUp("sam@example.com")
        assertEquals("{\"type\":\"signup\",\"email\":\"sam@example.com\"}", server.takeRequest().text())
        auth.updatePassword("abcdefghij2", verified)
        server.takeRequest().let {
            assertEquals("PUT", it.method)
            assertEquals("/auth/v1/user", it.path)
            assertEquals("Bearer new-access", it.getHeader("Authorization"))
        }
    }

    @Test
    fun signOutRemovesTheSessionFirstEvenWhenTheServerIsUnreachable() = runTest {
        val store = MemorySessionStore(session().encoded())
        val auth = SupabaseAuth(http, store) { unixNow }
        var observed: AuthSession? = session()
        auth.onSessionChange { observed = it }
        server.shutdown()
        auth.signOutLocal()
        assertNull(auth.session)
        assertNull(store.load())
        assertNull(observed)
    }

    @Test
    fun anExpiringSessionIsRefreshedAndARefusedRefreshSignsOut() = runTest {
        val auth = auth(session(expiresAt = unixNow + 30))
        server.enqueue(json(200, tokenBody(access = "refreshed")))
        assertEquals("refreshed", auth.validSession().accessToken)
        server.takeRequest().let {
            assertEquals("/auth/v1/token?grant_type=refresh_token", it.path)
            assertEquals("{\"refresh_token\":\"refresh-token\"}", it.text())
        }
        unixNow += 4_000
        server.enqueue(json(400, """{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token"}"""))
        try {
            auth.validSession()
            fail("refreshed")
        } catch (error: AuthApiException) {
            assertEquals("refresh_token_not_found", error.code)
        }
        assertNull(auth.session)
    }

    @Test
    fun transportReadsAndWritesTheChallengeTablesExactly() = runTest {
        val transport = SupabaseChallengeTransport(http, auth())
        val record = ChallengeRecord(UUID.fromString("AAAAAAAA-0000-4000-8000-000000000001"), owner, 1_791_414_000.0, "Europe/Jersey")
        server.enqueue(json(200, "[]"))
        assertNull(transport.fetchChallenge(owner))
        server.takeRequest().let {
            assertEquals("/rest/v1/challenges?select=*&owner_id=eq.6F1C2A43-0B55-4B5E-9F3D-2C1A7E9B4D10", it.path)
            assertEquals("Bearer access-token", it.getHeader("Authorization"))
        }
        server.enqueue(MockResponse().setResponseCode(201))
        transport.insertChallenge(record)
        server.takeRequest().let {
            assertEquals("/rest/v1/challenges?on_conflict=owner_id", it.path)
            assertEquals("resolution=ignore-duplicates,return=minimal", it.getHeader("Prefer"))
            assertEquals("{\"id\":\"AAAAAAAA-0000-4000-8000-000000000001\",\"owner_id\":\"6F1C2A43-0B55-4B5E-9F3D-2C1A7E9B4D10\"," +
                "\"start_time\":1791414000,\"time_zone\":\"Europe\\/Jersey\"}", it.text())
        }
        // An unmigrated server: the record without a zone reads as Jersey; inserting one is explained.
        server.enqueue(json(200, """[{"id":"AAAAAAAA-0000-4000-8000-000000000001","owner_id":"$owner","start_time":1791414000}]"""))
        assertEquals(record, transport.fetchChallenge(owner))
        server.takeRequest()
        server.enqueue(json(400, """{"code":"PGRST204","details":null,"hint":null,"message":"Could not find the 'time_zone' column of 'challenges' in the schema cache"}"""))
        try {
            transport.insertChallenge(record)
            fail("inserted")
        } catch (error: ChallengeSyncException) {
            assertEquals(ChallengeSyncError.SERVER_NEEDS_TIME_ZONE_UPDATE, error.error)
        }
        server.takeRequest()
    }

    @Test
    fun uploadsSendParentsFirstInBatchesAndFetchPagesSkipUnreadableRows() = runTest {
        val transport = SupabaseChallengeTransport(http, auth())
        val challengeID = UUID.randomUUID()
        val day = ChallengeCalendar(ZoneId.of("Europe/Jersey")).startOfDay(syncDate)
        val pours = (0 until 250).map { Activity(UUID.randomUUID(), day, syncDate + it, Action.Pour(10), null, "DEVICE") }
        val undo = Activity(UUID.randomUUID(), day, syncDate - 10, Action.UndoLatestPour, pours.last().id, "DEVICE")
        val events = (listOf(undo) + pours).map { ChallengeEvent(owner, challengeID, it) }
        repeat(2) { server.enqueue(MockResponse().setResponseCode(201)) }
        transport.upload(events, owner)
        val first = Wire.json.parseToJsonElement(server.takeRequest().text()).jsonArray
        val second = server.takeRequest().let {
            assertEquals("/rest/v1/challenge_events?on_conflict=owner_id,id", it.path)
            Wire.json.parseToJsonElement(it.text()).jsonArray
        }
        assertEquals(200, first.size)
        assertEquals(51, second.size)
        assertEquals(Challenge.uuidString(undo.id), second.last().jsonObject["id"].toString().trim('"'))
        assertFalse(first.toString().contains("received_at"))

        val good = """{"id":"${pours[0].id}","owner_id":"$owner","challenge_id":"$challengeID","activity":${Wire.text(Wire.encode(pours[0]))},"received_at":"2026-10-08T12:00:01.123456+00:00"}"""
        val unreadable = """{"id":"${UUID.randomUUID()}","owner_id":"$owner","challenge_id":"$challengeID","activity":{"id":"x","action":{"somethingNew":{}}},"received_at":"2026-10-08T12:00:01+00:00"}"""
        server.enqueue(json(200, "[" + (List(499) { good } + unreadable).joinToString(",") + "]"))
        server.enqueue(json(200, "[$good]"))
        val fetched = transport.fetchEvents(owner, challengeID)
        assertEquals(500, fetched.events.size)
        assertEquals(1, fetched.skipped)
        assertTrue(server.takeRequest().path!!.endsWith("&order=id.asc&offset=0&limit=500"))
        assertTrue(server.takeRequest().path!!.endsWith("&order=id.asc&offset=500&limit=500"))
        assertEquals("1 entry from the server could not be read and was skipped. Updating Daily Challenge may show it.",
            skippedRowsNotice(fetched.skipped))
    }

    @Test
    fun fetchReadsTargetAndScheduleRowsAndSkipsOutOfRangeOrFutureOnes() = runTest {
        val transport = SupabaseChallengeTransport(http, auth())
        val challengeID = UUID.randomUUID()
        val day = ChallengeCalendar(ZoneId.of("Europe/Jersey")).startOfDay(syncDate)
        fun row(action: String): String {
            val id = Challenge.uuidString(UUID.randomUUID())
            return "{\"id\":\"$id\",\"owner_id\":\"$owner\",\"challenge_id\":\"$challengeID\",\"received_at\":\"2026-10-08T12:00:01+00:00\"," +
                "\"activity\":{\"id\":\"$id\",\"day\":${day.toLong()},\"recordedAt\":${syncDate.toLong()},\"deviceID\":\"PHONE\",\"action\":$action}}"
        }
        val extra = Challenge.uuidString(UUID.randomUUID())
        server.enqueue(json(200, listOf(
            row("""{"setWater":{"goal":3000,"pour":250}}"""),
            row("""{"setTarget":{"_0":"walk","name":"Yoga","amount":30,"unit":"minutes","icon":"yoga"}}"""),
            row("""{"scheduleExtra":{"id":"$extra","weekdays":[1,2,3,4,5]}}"""),
            row("""{"setTarget":{"_0":"walk","name":"Yoga","amount":301,"unit":"minutes"}}"""),
            row("""{"setTimer":{"minutes":30}}"""),
        ).joinToString(",", "[", "]")))
        val fetched = transport.fetchEvents(owner, challengeID)
        server.takeRequest()
        assertEquals(listOf(Action.SetWater(3000, 250), Action.SetTarget(TargetSlot.WALK, "Yoga", 30, TargetUnit.MINUTES, "yoga"),
            Action.ScheduleExtra(UUID.fromString(extra), weekdays = listOf(1L, 2L, 3L, 4L, 5L))), fetched.events.map { it.activity.action })
        assertEquals(2, fetched.skipped)
        assertEquals("2 entries from the server could not be read and were skipped. Updating Daily Challenge may show them.",
            skippedRowsNotice(fetched.skipped))
    }

    @Test
    fun aSessionForAnotherAccountNeverSyncs() = runTest {
        val transport = SupabaseChallengeTransport(http, auth(session(user = UUID.randomUUID())))
        try {
            transport.fetchChallenge(owner)
            fail("fetched")
        } catch (error: ChallengeSyncException) {
            assertEquals(ChallengeSyncError.WRONG_OWNER, error.error)
        }
        assertEquals(0, server.requestCount)
    }

    @Test
    fun accountDeletionCallsTheRpcAndExplainsAMissingMigration() = runTest {
        val deletion = SupabaseAccountDeletion(http, auth())
        server.enqueue(MockResponse().setResponseCode(204))
        deletion.deleteAccount(owner)
        server.takeRequest().let {
            assertEquals("POST", it.method)
            assertEquals("/rest/v1/rpc/delete_own_account", it.path)
            assertEquals("{}", it.text())
            assertEquals("Bearer access-token", it.getHeader("Authorization"))
        }
        server.enqueue(json(404, """{"code":"PGRST202","details":"Searched for the function public.delete_own_account without parameters","hint":null,"message":"Could not find the function public.delete_own_account without parameters in the schema cache"}"""))
        try {
            deletion.deleteAccount(owner)
            fail("deleted")
        } catch (error: AccountDeletionException) {
            assertEquals(AccountDeletionError.SERVER_NEEDS_UPDATE, error.error)
        }
        try {
            deletion.deleteAccount(UUID.randomUUID())
            fail("deleted another account")
        } catch (error: AccountDeletionException) {
            assertEquals(AccountDeletionError.WRONG_ACCOUNT, error.error)
        }
    }
}
