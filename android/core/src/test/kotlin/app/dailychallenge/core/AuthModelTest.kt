package app.dailychallenge.core

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.UUID

/** A scripted Supabase Auth: each call returns or throws what the test queued. */
class FakeAuthBackend : AuthBackend {
    override var session: AuthSession? = null
    private val listeners = ArrayList<(AuthSession?) -> Unit>()
    val calls = ArrayList<String>()
    var failure: Exception? = null
    var updateFailure: Exception? = null
    var signUpResult = SignUpResult(null, false)
    var verified: AuthSession? = null

    private fun maybeFail() { failure?.let { failure = null; throw it } }
    private fun keep(value: AuthSession?) { session = value; listeners.forEach { it(value) } }

    override fun onSessionChange(listener: (AuthSession?) -> Unit) { listeners += listener }
    override suspend fun signIn(email: String, password: String): AuthSession {
        calls += "signIn $email"; maybeFail()
        return session(UUID.randomUUID(), email).also(::keep)
    }
    override suspend fun signUp(email: String, password: String): SignUpResult {
        calls += "signUp $email"; maybeFail()
        signUpResult.session?.let(::keep)
        return signUpResult
    }
    override suspend fun verifyOtp(email: String, token: String, type: OtpType): AuthSession? {
        calls += "verify ${type.wire} $token"; maybeFail(); return verified
    }
    override fun adopt(session: AuthSession) { calls += "adopt"; keep(session) }
    override suspend fun resetPasswordForEmail(email: String) { calls += "recover $email"; maybeFail() }
    override suspend fun resendSignUp(email: String) { calls += "resend $email"; maybeFail() }
    override suspend fun updatePassword(password: String, session: AuthSession?) {
        calls += "update"; updateFailure?.let { updateFailure = null; throw it }
    }
    override suspend fun signOutLocal(session: AuthSession?) {
        calls += "signOut"
        if (session == null || session == this.session) keep(null)
    }

    companion object {
        fun session(id: UUID = UUID.randomUUID(), email: String = "sam@example.com") = AuthSession("a", "r", Long.MAX_VALUE, id, email)
    }
}

/** Ports of the Swift sign-in, sign-up and deletion flow tests over a scripted backend. */
class AuthModelTest {
    private var clock = 1_000.0
    private val backend = FakeAuthBackend()
    private val model = AuthModel(backend, now = { clock }).also { it.start() }

    @Test
    fun passwordAndCodeRulesMatchTheAppleApps() {
        assertEquals(AuthModel.PASSWORD_RULE, AuthModel.passwordProblem("short1"))
        assertEquals(AuthModel.PASSWORD_RULE, AuthModel.passwordProblem("abcdefghijk"))
        assertEquals(AuthModel.PASSWORD_RULE, AuthModel.passwordProblem("12345678901"))
        assertEquals(AuthModel.PASSWORD_RULE, AuthModel.passwordProblem("ééééééééé1"))
        assertNull(AuthModel.passwordProblem("abcdefghi1"))
        assertTrue(AuthModel.isCompleteCode("123456") && AuthModel.isCompleteCode("1234567890"))
        assertFalse(AuthModel.isCompleteCode("12345") || AuthModel.isCompleteCode("12345678901") || AuthModel.isCompleteCode("12345a"))
    }

    @Test
    fun signInClearsThePasswordAndAnUnconfirmedAccountGoesToItsCode() = runTest {
        model.email = " sam@example.com "
        model.password = "abcdefghi1"
        model.signIn()
        assertEquals("signIn sam@example.com", backend.calls.last())
        assertEquals("", model.password)
        assertTrue(model.ownerID != null)
        model.signOut()
        assertNull(model.ownerID)
        model.email = "sam@example.com"
        model.password = "abcdefghi1"
        backend.failure = AuthApiException(400, "email_not_confirmed", "Email not confirmed")
        model.signIn()
        assertEquals(AuthStep.ConfirmSignUp("sam@example.com"), model.authStep)
        assertTrue(model.notice!!.startsWith("Confirm your email"))
        assertEquals("", model.password)
    }

    @Test
    fun signUpThenCodeThenSignedIn() = runTest {
        model.signUp("sam@example.com", "short")
        assertEquals(AuthModel.PASSWORD_RULE, model.errorMessage)
        assertTrue(backend.calls.isEmpty())
        model.signUp("sam@example.com", "abcdefghi1")
        assertEquals(AuthStep.ConfirmSignUp("sam@example.com"), model.authStep)
        assertEquals(60, model.resendWait(clock))
        assertFalse(model.canResend)
        clock += 61
        assertTrue(model.canResend)
        model.confirmSignUp("12 34")
        assertEquals("Enter the code from the email.", model.errorMessage)
        val owner = UUID.randomUUID()
        backend.verified = FakeAuthBackend.session(owner)
        model.confirmSignUp("123456")
        assertEquals(listOf("verify signup 123456", "adopt"), backend.calls.takeLast(2))
        assertEquals(owner, model.ownerID)
        assertEquals(AuthStep.SignIn, model.authStep)
    }

    @Test
    fun anExistingAddressIsSentToSignInWithoutSayingWhoHasAnAccount() = runTest {
        backend.signUpResult = SignUpResult(null, true)
        model.signUp("sam@example.com", "abcdefghi1")
        assertEquals(AuthStep.SignIn, model.authStep)
        assertEquals("An account with this email already exists, try signing in.", model.errorMessage)
    }

    @Test
    fun aFailedPasswordSaveSignsTheRecoverySessionOutAndNeverShowsItSignedIn() = runTest {
        model.requestPasswordReset("sam@example.com")
        assertEquals(AuthStep.ResetPassword("sam@example.com"), model.authStep)
        backend.verified = FakeAuthBackend.session()
        backend.updateFailure = NetworkException(IOException("offline"))
        var sawSignedIn = false
        model.onSessionChange { if (it != null) sawSignedIn = true }
        model.completePasswordReset("12345678", "abcdefghi2")
        assertFalse(sawSignedIn)
        assertNull(model.ownerID)
        assertEquals(AuthStep.ForgotPassword, model.authStep)
        assertTrue(model.errorMessage!!.startsWith("Your new password was not saved: Can't reach the server."))
        assertEquals("signOut", backend.calls.last())

        model.requestPasswordReset("sam@example.com")
        backend.updateFailure = AuthApiException(422, "same_password", "same")
        model.completePasswordReset("12345678", "abcdefghi2")
        assertEquals("That was already your password. You're signed in.", model.status)
        assertTrue(model.ownerID != null)
    }

    @Test
    fun accountDeletionChangesNothingUnlessTheServerConfirms() = runTest {
        model.email = "sam@example.com"; model.password = "abcdefghi1"
        model.signIn()
        val owner = model.ownerID!!
        var reachable = false
        var deletedOnServer = 0
        model.accountDeletion = object : AccountDeletionTransport {
            override suspend fun deleteAccount(ownerID: UUID) {
                if (!reachable) throw NetworkException(IOException("offline"))
                deletedOnServer++
            }
        }
        val removed = ArrayList<UUID>()
        assertFalse(model.deleteAccount { removed += it })
        assertEquals(owner, model.ownerID)
        assertTrue(removed.isEmpty())
        assertTrue(model.errorMessage!!.startsWith("Your account was not deleted and nothing was removed."))
        reachable = true
        assertTrue(model.deleteAccount { removed += it })
        assertEquals(1, deletedOnServer)
        assertEquals(listOf(owner), removed)
        assertNull(model.ownerID)
        assertNull(backend.session)
        assertEquals("Your account and all its challenge history have been deleted.", model.notice)
    }
}
