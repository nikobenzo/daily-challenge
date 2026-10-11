package app.dailychallenge.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Contrast
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MarkEmailUnread
import androidx.compose.material.icons.outlined.Password
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.Pin
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.dailychallenge.android.AppGraph
import app.dailychallenge.android.Appearance
import app.dailychallenge.core.AuthModel
import app.dailychallenge.core.AuthStep
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

val AuthStep.title: String
    get() = when (this) {
        AuthStep.SignIn -> "Sign in"
        AuthStep.CreateAccount -> "Create account"
        AuthStep.ForgotPassword -> "Reset password"
        is AuthStep.ConfirmSignUp -> "Enter the code"
        is AuthStep.ResetPassword -> "New password"
    }

val AuthStep.subtitle: String
    get() = when (this) {
        AuthStep.SignIn -> "Use your Daily Challenge email and password. The same account works on all your devices."
        AuthStep.CreateAccount -> "Choose the email and password you'll use on every device. We'll email you a code to confirm it's yours."
        AuthStep.ForgotPassword -> "Enter the email you signed up with and we'll send you a code."
        is AuthStep.ConfirmSignUp -> codeSubtitle(email)
        is AuthStep.ResetPassword -> codeSubtitle(email)
    }

private fun codeSubtitle(email: String) =
    "We sent a code to $email. Codes expire, so use the one in the newest email. Check your spam folder if it hasn't arrived."

val AuthStep.icon: ImageVector
    get() = when (this) {
        AuthStep.SignIn -> Icons.Filled.Cloud
        AuthStep.CreateAccount -> Icons.Outlined.PersonAdd
        AuthStep.ForgotPassword -> Icons.Outlined.Key
        is AuthStep.ConfirmSignUp -> Icons.Outlined.Email
        is AuthStep.ResetPassword -> Icons.Outlined.Lock
    }

/**
 * Signed out: sign in, create an account, or reset a password with an emailed code. The same
 * flow and rules as the Mac and iPhone (`AuthModel`); passwords are never stored.
 */
@Composable
fun AuthScreen(graph: AppGraph) {
    val auth = graph.auth
    auth.observe()
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val step = auth.authStep
    LaunchedEffect(step) { focus.clearFocus() }

    val canCreate = auth.email.isNotEmpty() && AuthModel.passwordProblem(auth.password) == null && auth.password == auth.passwordConfirmation
    val canReset = AuthModel.isCompleteCode(auth.code) && AuthModel.passwordProblem(auth.newPassword) == null &&
        auth.newPassword == auth.passwordConfirmation
    fun submitSignIn() { if (auth.email.isNotEmpty() && auth.password.isNotEmpty()) scope.launch { auth.signIn() } }
    fun submitSignUp() { if (canCreate) scope.launch { auth.signUp(auth.email, auth.password) } }
    fun submitResetRequest() { if (auth.email.isNotEmpty()) scope.launch { auth.requestPasswordReset(auth.email) } }
    fun submitConfirmation() { if (AuthModel.isCompleteCode(auth.code)) scope.launch { auth.confirmSignUp(auth.code) } }
    fun submitReset() { if (canReset) scope.launch { auth.completePasswordReset(auth.code, auth.newPassword) } }

    PhoneScreen {
        PhoneHeader()
        GlassCard {
            Column(Modifier.fillMaxWidth().padding(horizontal = Size.sectionHorizontal, vertical = 24.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    HeroIcon(step.icon)
                    Text(step.title, style = Type.screenTitle, color = P.textPrimary,
                        modifier = Modifier.semantics { heading() }.testTag("auth-title"))
                    Text(step.subtitle, style = Type.caption, color = P.textSecondary, textAlign = TextAlign.Center)
                }
                auth.notice?.let { notice ->
                    Row(Modifier.fillMaxWidth().testTag("auth-notice"), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
                        Icon(if (step.isCode) Icons.Outlined.MarkEmailUnread else Icons.Outlined.Info, null, tint = P.textSecondary,
                            modifier = Modifier.size(16.dp))
                        Text(notice, style = Type.caption, color = P.textSecondary, textAlign = TextAlign.Center)
                    }
                }
                auth.errorMessage?.let { error ->
                    Row(Modifier.fillMaxWidth().testTag("auth-error").semantics(mergeDescendants = true) { contentDescription = "Error: $error" },
                        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
                        Icon(Icons.Filled.Warning, null, tint = P.danger, modifier = Modifier.size(16.dp))
                        Text(error, style = Type.caption, color = P.danger, textAlign = TextAlign.Center)
                    }
                }
                val enabled = !auth.isBusy
                @Composable fun email(onSubmit: () -> Unit) = DesignField(auth.email, { auth.email = it }, "Email", Icons.Outlined.Email,
                    keyboardType = KeyboardType.Email, enabled = enabled, onSubmit = onSubmit, testTag = "auth-email")
                @Composable fun primary(text: String, icon: ImageVector, ok: Boolean, action: () -> Unit) =
                    PrimaryPill(text, action, icon = icon, enabled = ok && !auth.isBusy, busy = auth.isBusy, height = Size.largePill,
                        style = Type.appName, modifier = Modifier.testTag("auth-primary"))
                @Composable fun backToSignIn() = LinkButton("Back to sign in", { auth.show(AuthStep.SignIn) },
                    icon = Icons.AutoMirrored.Filled.ArrowBack)
                @Composable fun code(onSubmit: () -> Unit) = DesignField(auth.code, { value ->
                    auth.code = value.filter { it in '0'..'9' }.take(AuthModel.CODE_LENGTHS.last)
                }, "Code from the email", Icons.Outlined.Pin, keyboardType = KeyboardType.NumberPassword, monospaced = true,
                    enabled = enabled, onSubmit = onSubmit, testTag = "auth-code")

                when (step) {
                    AuthStep.SignIn -> {
                        email { focus.moveFocus(androidx.compose.ui.focus.FocusDirection.Down) }
                        DesignField(auth.password, { auth.password = it }, "Password", Icons.Outlined.Lock, secure = true,
                            imeAction = ImeAction.Go, enabled = enabled, onSubmit = ::submitSignIn, testTag = "auth-password")
                        primary("Sign in", Icons.AutoMirrored.Filled.ArrowForward, auth.email.isNotEmpty() && auth.password.isNotEmpty(), ::submitSignIn)
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            LinkButton("Create account", { auth.show(AuthStep.CreateAccount) }, modifier = Modifier.testTag("auth-create-account"))
                            Spacer(Modifier.weight(1f))
                            LinkButton("Forgot password?", { auth.show(AuthStep.ForgotPassword) })
                        }
                    }
                    AuthStep.CreateAccount -> {
                        email { focus.moveFocus(androidx.compose.ui.focus.FocusDirection.Down) }
                        DesignField(auth.password, { auth.password = it }, "Choose a password", Icons.Outlined.Lock, secure = true,
                            enabled = enabled, onSubmit = { focus.moveFocus(androidx.compose.ui.focus.FocusDirection.Down) })
                        DesignField(auth.passwordConfirmation, { auth.passwordConfirmation = it }, "Repeat password", Icons.Outlined.Shield,
                            secure = true, imeAction = ImeAction.Go, enabled = enabled, onSubmit = ::submitSignUp)
                        PasswordRules(auth.password, auth.passwordConfirmation)
                        primary("Create account", Icons.Outlined.PersonAdd, canCreate, ::submitSignUp)
                        backToSignIn()
                    }
                    AuthStep.ForgotPassword -> {
                        email(::submitResetRequest)
                        primary("Send code", Icons.Outlined.Email, auth.email.isNotEmpty(), ::submitResetRequest)
                        backToSignIn()
                    }
                    is AuthStep.ConfirmSignUp -> {
                        code(::submitConfirmation)
                        primary("Confirm email", Icons.Filled.Check, AuthModel.isCompleteCode(auth.code), ::submitConfirmation)
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            LinkButton("Different email", { auth.show(AuthStep.CreateAccount) })
                            Spacer(Modifier.weight(1f))
                            ResendControl(auth, graph.clock)
                        }
                    }
                    is AuthStep.ResetPassword -> {
                        code { focus.moveFocus(androidx.compose.ui.focus.FocusDirection.Down) }
                        DesignField(auth.newPassword, { auth.newPassword = it }, "New password", Icons.Outlined.Password, secure = true,
                            enabled = enabled, onSubmit = { focus.moveFocus(androidx.compose.ui.focus.FocusDirection.Down) })
                        DesignField(auth.passwordConfirmation, { auth.passwordConfirmation = it }, "Repeat password", Icons.Outlined.Shield,
                            secure = true, imeAction = ImeAction.Go, enabled = enabled, onSubmit = ::submitReset)
                        PasswordRules(auth.newPassword, auth.passwordConfirmation)
                        primary("Save new password", Icons.Filled.Check, canReset, ::submitReset)
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            backToSignIn()
                            Spacer(Modifier.weight(1f))
                            ResendControl(auth, graph.clock)
                        }
                    }
                }
            }
        }
        AppearanceCard(graph)
    }
}

@Composable
fun AppearanceCard(graph: AppGraph) {
    GlassCard {
        Column(Modifier.padding(horizontal = Size.sectionHorizontal, vertical = 8.dp).padding(bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)) {
            SettingRow(Icons.Filled.Contrast, "Appearance")
            Segmented(Appearance.entries.map { it to it.label }, graph.appearance, graph::chooseAppearance)
        }
    }
}

/** 10+ · Aa · 0-9 · Match: each chip turns green with a check as its rule is met. */
@Composable
fun PasswordRules(password: String, confirmation: String) {
    val rules = listOf(
        Triple("10+", "at least ${AuthModel.MINIMUM_PASSWORD_LENGTH} characters",
            app.dailychallenge.core.Challenge.graphemeCount(password) >= AuthModel.MINIMUM_PASSWORD_LENGTH),
        Triple("Aa", "a letter", AuthModel.hasLetter(password)),
        Triple("0-9", "a number", AuthModel.hasDigit(password)),
        Triple("Match", "both passwords match", confirmation.isNotEmpty() && password == confirmation),
    )
    val spoken = "Password rules: " + rules.joinToString("; ") { "${it.second}, ${if (it.third) "met" else "not met"}" }
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = spoken },
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        rules.forEach { (text, _, met) ->
            Row(Modifier.heightIn(min = 26.dp).clip(CircleShape).background(if (met) P.doneTint else P.controlFill).padding(horizontal = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                if (met) Icon(Icons.Filled.Check, null, tint = P.doneText, modifier = Modifier.size(12.dp))
                else Spacer(Modifier.size(6.dp).clip(CircleShape).background(P.textTertiary))
                Text(text, style = Type.badge, color = if (met) P.doneText else P.textSecondary)
            }
        }
    }
}

/** Shows the wait instead of a dead button while the 60-second resend limit applies. */
@Composable
fun ResendControl(auth: AuthModel, clock: () -> Double) {
    auth.observe()
    val scope = rememberCoroutineScope()
    var now by remember { mutableDoubleStateOf(clock()) }
    LaunchedEffect(auth.resendAvailableAt) {
        while (true) { now = clock(); delay(1_000) }
    }
    val wait = auth.resendWait(now)
    if (wait > 0) {
        Row(Modifier.heightIn(min = 34.dp).clip(CircleShape).background(P.controlFill).padding(horizontal = 14.dp)
            .semantics(mergeDescendants = true) { contentDescription = "You can request a new code in $wait seconds" },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.Refresh, null, tint = P.textTertiary, modifier = Modifier.size(16.dp))
            Text("${wait}s", style = Type.pill, color = P.textTertiary)
        }
    } else {
        TintedPill("Resend", { scope.launch { auth.resendCode() } }, icon = Icons.Filled.Refresh, height = 34.dp, foreground = P.accentText,
            modifier = Modifier.semantics { contentDescription = "Resend code" }.alpha(1f))
    }
}
