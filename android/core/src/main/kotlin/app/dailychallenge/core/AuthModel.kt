package app.dailychallenge.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.UUID
import kotlin.math.ceil

/** Which signed-out screen is showing. Code steps carry the address the code was sent to. */
sealed interface AuthStep {
    data object SignIn : AuthStep
    data object CreateAccount : AuthStep
    data object ForgotPassword : AuthStep
    data class ConfirmSignUp(val email: String) : AuthStep
    data class ResetPassword(val email: String) : AuthStep

    val isCode: Boolean get() = this is ConfirmSignUp || this is ResetPassword
}

/**
 * Email and password accounts with emailed codes (Swift `AuthModel`): the same flow, rules and
 * words as the Mac and iPhone. Tells the tracker which account is signed in. Passwords live
 * only in these fields until the request is sent, then are cleared; only session tokens are kept.
 */
class AuthModel(
    private val backend: AuthBackend?,
    var accountDeletion: AccountDeletionTransport? = null,
    private val now: () -> Double = ChallengeTime::now,
    missingConfiguration: String? = null,
) {
    private val _changes = MutableStateFlow(0L)
    val changes: StateFlow<Long> = _changes
    private fun changed() { _changes.value = _changes.value + 1 }

    var email = ""
        set(value) { field = value; changed() }
    var password = ""
        set(value) { field = value; changed() }
    var passwordConfirmation = ""
        set(value) { field = value; changed() }
    var newPassword = ""
        set(value) { field = value; changed() }
    var code = ""
        set(value) { field = value; changed() }
    var authStep: AuthStep = AuthStep.SignIn
        private set
    var signedInEmail: String? = null
        private set
    var ownerID: UUID? = null
        private set
    var isBusy = false
        private set
    var status = "Restoring session…"
        private set
    var errorMessage: String? = null
        private set
    val configurationReady: Boolean = backend != null
    /** Guidance for the current sign-up or reset step, such as where a code was sent. */
    var notice: String? = null
        private set
    var resendAvailableAt: Double? = null
        private set

    private var tracker: Tracker? = null
    private val sessionObservers = ArrayList<(UUID?) -> Unit>()
    /** Set while a recovery code's session waits for its new password. */
    private var holdingRecoverySession = false
    private var started = false

    init {
        if (backend == null) {
            status = "Configuration unavailable"
            errorMessage = missingConfiguration
        }
    }

    /** Offline fixtures: a fixed account or screen, no server. */
    fun applyFixture(ownerID: UUID?, email: String = "fixture@example.invalid", step: AuthStep = AuthStep.SignIn,
                     notice: String? = null, errorMessage: String? = null, resendAvailableAt: Double? = null) {
        this.ownerID = ownerID
        signedInEmail = if (ownerID == null) null else email
        authStep = step
        this.notice = notice
        this.errorMessage = errorMessage
        this.resendAvailableAt = resendAvailableAt
        status = "Offline fixture"
        changed()
    }

    fun onSessionChange(observer: (UUID?) -> Unit) { sessionObservers += observer }

    fun attachTracker(tracker: Tracker) {
        this.tracker = tracker
        tracker.activate(ownerID)
    }

    /** Follows the backend's session: the one restored at launch, refreshes and sign-outs. */
    fun start() {
        val backend = backend ?: return
        if (started) return
        started = true
        backend.onSessionChange { if (!holdingRecoverySession) activate(it) }
        activate(backend.session)
    }

    private fun activate(session: AuthSession?) {
        if (session == null) {
            ownerID = null
            signedInEmail = null
            status = "Signed out"
        } else {
            signedInEmail = session.email
            if (ownerID != session.userID) {
                ownerID = session.userID
                status = "Signed in"
            }
        }
        tracker?.activate(ownerID)
        sessionObservers.forEach { it(ownerID) }
        changed()
    }

    suspend fun signIn() {
        val backend = backend ?: return
        if (isBusy) return
        val address = email.trim()
        if (!address.contains("@") || password.isEmpty()) {
            errorMessage = "Enter your app account email and password."
            changed()
            return
        }
        beginAttempt("Signing in…")
        try {
            val session = backend.signIn(address, password)
            activate(session)
            status = "Signed in."
        } catch (error: CancellationException) {
            throw error
        } catch (error: AuthApiException) {
            if (error.code == "email_not_confirmed") {
                // The account exists but its sign-up code was never entered.
                show(AuthStep.ConfirmSignUp(address))
                notice = "Confirm your email to finish creating your account. Enter the code we sent to $address, or send a new one."
                status = "Email not confirmed yet"
            } else {
                errorMessage = describe(error)
                status = "Sign-in failed"
            }
        } catch (error: Exception) {
            errorMessage = describe(error)
            status = "Sign-in failed"
        } finally {
            endAttempt()
        }
    }

    /** Switches signed-out screens. Never carries a typed password or code across screens. */
    fun show(step: AuthStep) {
        authStep = step
        code = ""
        clearSecrets()
        notice = null
        errorMessage = null
        resendAvailableAt = null
        changed()
    }

    /** With Confirm email on, Supabase returns no session until the emailed code is entered. */
    suspend fun signUp(email: String, password: String) {
        val backend = backend ?: return
        if (isBusy) return
        val address = email.trim()
        this.email = address
        if (!address.contains("@")) {
            clearSecrets()
            errorMessage = "Enter your email address."
            changed()
            return
        }
        passwordProblem(password)?.let {
            clearSecrets()
            errorMessage = it
            changed()
            return
        }
        beginAttempt("Creating account…")
        try {
            val result = backend.signUp(address, password)
            if (result.session != null) {
                activate(result.session)
                status = "Account created. You're signed in."
                return
            }
            if (result.alreadyRegistered) {
                show(AuthStep.SignIn)
                errorMessage = ACCOUNT_EXISTS
                status = "Account already exists"
                return
            }
            show(AuthStep.ConfirmSignUp(address))
            resendAvailableAt = now() + RESEND_INTERVAL
            notice = "We emailed a code to $address. Enter it to finish creating your account."
            status = "Check your email for a code"
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            errorMessage = describe(error)
            status = "Account not created"
            if ((error as? AuthApiException)?.code in setOf("user_already_exists", "email_exists")) {
                show(AuthStep.SignIn)
                errorMessage = ACCOUNT_EXISTS
            }
        } finally {
            endAttempt()
        }
    }

    suspend fun confirmSignUp(code: String) {
        val backend = backend ?: return
        val step = authStep as? AuthStep.ConfirmSignUp ?: return
        if (isBusy) return
        val token = validCode(code) ?: return
        beginAttempt("Checking code…")
        try {
            val session = backend.verifyOtp(step.email, token, OtpType.SIGNUP)
            show(AuthStep.SignIn)
            if (session != null) {
                backend.adopt(session)
                activate(session)
                status = "Email confirmed. You're signed in."
            } else {
                email = step.email
                notice = "Your email is confirmed. Sign in with your password."
                status = "Email confirmed"
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            errorMessage = describe(error)
            status = "Code not accepted"
        } finally {
            endAttempt()
        }
    }

    /** Supabase answers the same way whether or not the address has an account. */
    suspend fun requestPasswordReset(email: String) {
        val backend = backend ?: return
        if (isBusy) return
        val address = email.trim()
        this.email = address
        if (!address.contains("@")) {
            errorMessage = "Enter the email address you signed up with."
            changed()
            return
        }
        beginAttempt("Sending code…")
        try {
            backend.resetPasswordForEmail(address)
            show(AuthStep.ResetPassword(address))
            resendAvailableAt = now() + RESEND_INTERVAL
            notice = "If $address has an account, we emailed it a code. Enter it with your new password."
            status = "Check your email for a code"
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            errorMessage = describe(error)
            status = "Code not sent"
            if ((error as? AuthApiException)?.code == "over_email_send_rate_limit") resendAvailableAt = now() + RESEND_INTERVAL
        } finally {
            endAttempt()
        }
    }

    /**
     * The code and the new password are one step. The recovery code's session is kept only
     * once the new password is saved; otherwise it is signed out on this device, so an
     * abandoned or failed reset never leaves anyone signed in.
     */
    suspend fun completePasswordReset(code: String, newPassword: String) {
        val backend = backend ?: return
        val step = authStep as? AuthStep.ResetPassword ?: return
        if (isBusy) return
        val token = validCode(code) ?: run { clearSecrets(); return }
        passwordProblem(newPassword)?.let {
            clearSecrets()
            errorMessage = it
            changed()
            return
        }
        beginAttempt("Checking code…")
        holdingRecoverySession = true
        try {
            val session = try {
                backend.verifyOtp(step.email, token, OtpType.RECOVERY)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                errorMessage = describe(error)
                status = "Code not accepted"
                return
            }
            if (session == null) {
                errorMessage = "That code could not sign you in. Request a new one."
                status = "Code not accepted"
                return
            }
            val outcome = try {
                backend.updatePassword(newPassword, session)
                "Password updated. You're signed in."
            } catch (error: AuthApiException) {
                if (error.code == "same_password") "That was already your password. You're signed in."
                else { abandonReset(backend, session, step.email, describe(error)); return }
            } catch (error: CancellationException) {
                abandonReset(backend, session, step.email, null)
                throw error
            } catch (error: Exception) {
                abandonReset(backend, session, step.email, describe(error))
                return
            }
            show(AuthStep.SignIn)
            backend.adopt(session)
            holdingRecoverySession = false
            activate(session)
            status = outcome
        } finally {
            holdingRecoverySession = false
            endAttempt()
        }
    }

    private suspend fun abandonReset(backend: AuthBackend, session: AuthSession, address: String, reason: String?) {
        backend.signOutLocal(session)
        show(AuthStep.ForgotPassword)
        email = address
        errorMessage = if (reason == null) "The password reset was interrupted and your new password was not saved. Start again to get a new code."
        else "Your new password was not saved: $reason Start again to get a new code."
        status = "Password not changed"
    }

    /** Sends a fresh code for the current code step, at most once per resend interval. */
    suspend fun resendCode() {
        val backend = backend ?: return
        if (isBusy || !canResend) return
        beginAttempt("Sending a new code…")
        try {
            when (val step = authStep) {
                is AuthStep.ConfirmSignUp -> {
                    backend.resendSignUp(step.email)
                    notice = "We sent a new code to ${step.email}."
                }
                is AuthStep.ResetPassword -> {
                    backend.resetPasswordForEmail(step.email)
                    notice = "If ${step.email} has an account, we sent it a new code."
                }
                else -> return
            }
            resendAvailableAt = now() + RESEND_INTERVAL
            status = "Check your email for a code"
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            errorMessage = describe(error)
            status = "Code not sent"
            if ((error as? AuthApiException)?.code == "over_email_send_rate_limit") resendAvailableAt = now() + RESEND_INTERVAL
        } finally {
            endAttempt()
        }
    }

    val canResend: Boolean get() = resendWait(now()) == 0

    /** Whole seconds until another code may be requested; 0 when it can be sent now. */
    fun resendWait(at: Double): Int {
        val available = resendAvailableAt ?: return 0
        return maxOf(0, ceil(available - at).toInt())
    }

    /** Signs out on this device only, so the account's other devices stay signed in. */
    suspend fun signOut() {
        val backend = backend ?: return
        if (isBusy) return
        isBusy = true
        changed()
        try {
            backend.signOutLocal()
            activate(null)
            show(AuthStep.SignIn)
            errorMessage = null
        } finally {
            isBusy = false
            changed()
        }
    }

    /**
     * Permanently deletes the signed-in account and its synced history on the server. Nothing
     * on this device changes unless the server confirms; once deleted, the session is removed
     * here and `removeLocalData` erases this device's copies. Returns whether it was deleted.
     */
    suspend fun deleteAccount(removeLocalData: (UUID) -> Unit): Boolean {
        val owner = ownerID ?: return false
        val deletion = accountDeletion ?: return false
        if (isBusy) return false
        beginAttempt("Deleting account…")
        try {
            try {
                deletion.deleteAccount(owner)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                errorMessage = "Your account was not deleted and nothing was removed. ${describe(error)}"
                status = "Account not deleted"
                return false
            }
            // The account no longer exists. Signing out removes the saved session first, so it
            // succeeds offline too; the server's reply doesn't matter.
            backend?.signOutLocal()
            if (ownerID == owner) activate(null)
            show(AuthStep.SignIn)
            status = "Account deleted"
            try {
                removeLocalData(owner)
                notice = "Your account and all its challenge history have been deleted."
            } catch (error: Exception) {
                errorMessage = "Your account and its synced history were deleted, but the copy on this device " +
                    "could not be removed: ${error.message} Uninstalling the app removes it."
            }
            return true
        } finally {
            endAttempt()
        }
    }

    private fun beginAttempt(label: String) {
        isBusy = true
        errorMessage = null
        status = label
        changed()
    }

    private fun endAttempt() {
        // Passwords are sent only to Supabase Auth, never saved. Only session tokens are kept.
        clearSecrets()
        code = ""
        isBusy = false
        changed()
    }

    private fun clearSecrets() {
        password = ""
        passwordConfirmation = ""
        newPassword = ""
    }

    private fun validCode(value: String): String? {
        val digits = value.filterNot { it.isWhitespace() }
        if (!isCompleteCode(digits)) {
            code = ""
            errorMessage = "Enter the code from the email."
            changed()
            return null
        }
        return digits
    }

    companion object {
        const val RESEND_INTERVAL = 60.0
        /** New passwords only: existing accounts with shorter passwords still sign in. */
        const val MINIMUM_PASSWORD_LENGTH = 10
        /** Every length the Supabase "Email OTP length" setting allows. */
        val CODE_LENGTHS = 6..10
        const val PASSWORD_RULE = "Use at least $MINIMUM_PASSWORD_LENGTH characters, with at least one letter and one number."
        private const val ACCOUNT_EXISTS = "An account with this email already exists, try signing in."

        /** Null when a new password meets the rule; letters and digits are ASCII, as Supabase counts them. */
        fun passwordProblem(password: String): String? {
            val acceptable = Challenge.graphemeCount(password) >= MINIMUM_PASSWORD_LENGTH &&
                password.any { it in 'a'..'z' || it in 'A'..'Z' } && password.any { it in '0'..'9' }
            return if (acceptable) null else PASSWORD_RULE
        }

        fun hasLetter(password: String) = password.any { it in 'a'..'z' || it in 'A'..'Z' }
        fun hasDigit(password: String) = password.any { it in '0'..'9' }

        /** Whether a typed code is all digits and a length Supabase can send. */
        fun isCompleteCode(code: String): Boolean = code.length in CODE_LENGTHS && code.all { it in '0'..'9' }

        /** Plain English for the auth errors a person can act on; anything else keeps the server's words. */
        fun describe(error: Throwable): String {
            if (error is NetworkException) return "Can't reach the server. Check your internet connection and try again."
            if (error !is AuthApiException) return Tracker.describe(error)
            return when (error.code) {
                "otp_expired" -> "That code is wrong or has expired. Check the latest email, or request a new code."
                "user_already_exists", "email_exists" -> ACCOUNT_EXISTS
                "invalid_credentials" -> "That email and password don't match an account. Try again, or use Forgot password."
                "over_email_send_rate_limit" -> "Too many emails were requested. Wait a minute, then try again."
                "over_request_rate_limit" -> "Too many attempts. Wait a few minutes, then try again."
                "weak_password" -> "Choose a stronger password. ${error.message}"
                "same_password" -> "That is already your password. Choose a different one."
                "signup_disabled" -> "New accounts are switched off for this app right now."
                "email_address_not_authorized" -> "The app can't send email to that address yet. Try again later."
                "email_provider_disabled" -> "Email accounts are switched off for this app right now."
                "session_not_found", "session_expired" -> "Your session has ended. Sign in again, then try once more."
                "reauthentication_needed" -> "For security, sign out and use Forgot password to set a new password."
                else -> if (error.status == 429) "Too many attempts. Wait a few minutes, then try again." else error.message ?: "The server refused the request."
            }
        }
    }
}
