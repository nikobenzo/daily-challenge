import ChallengeSyncKit
import SwiftUI

/// Signed out: sign in, create an account, or reset a password with an emailed code.
/// The same flow and rules as the Mac (`AuthModel`); passwords are never stored.
struct AuthScreen: View {
    @Bindable var auth: AuthModel
    let app: PhoneApp
    @FocusState private var focus: Field?

    enum Field: Hashable { case email, password, confirmation, code, newPassword }

    var body: some View {
        PhoneScreen {
            PhoneHeader()
            GlassCard {
                VStack(spacing: 14) {
                    hero
                    if let notice = auth.notice {
                        Label(notice, systemImage: auth.authStep.isCode ? "envelope.badge" : "info.circle")
                            .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("auth-notice")
                    }
                    if let error = auth.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Fonts.caption).foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Error: \(error)")
                            .accessibilityIdentifier("auth-error")
                    }
                    form
                }
                .disabled(auth.isBusy)
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Space.xl)
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SettingRow(symbol: "circle.lefthalf.filled", title: "Appearance") { EmptyView() }
                    Picker("Appearance", selection: Bindable(app).appearance) {
                        Text("System").tag(AppearancePreference.system)
                        Text("Light").tag(AppearancePreference.light)
                        Text("Dark").tag(AppearancePreference.dark)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Space.s)
            }
        }
        .onChange(of: auth.authStep) { _, _ in focus = nil }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            HeroIcon(symbol: auth.authStep.symbol)
            Text(auth.authStep.title).font(Theme.Fonts.screenTitle).tracking(Theme.Tracking.screenTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("auth-title")
            Text(auth.authStep.subtitle).font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var form: some View {
        switch auth.authStep {
        case .signIn:
            emailField
            PhoneField(symbol: "lock", placeholder: "Password", text: $auth.password, secure: true,
                       contentType: .password, focus: $focus, field: .password, submit: submitSignIn)
            primary("Sign in", symbol: "arrow.right", enabled: !auth.email.isEmpty && !auth.password.isEmpty,
                    action: submitSignIn)
            HStack {
                Button("Create account") { auth.show(.createAccount) }.buttonStyle(LinkStyle())
                    .accessibilityIdentifier("auth-create-account")
                Spacer()
                Button("Forgot password?") { auth.show(.forgotPassword) }.buttonStyle(LinkStyle())
            }
            .frame(minHeight: 44)
        case .createAccount:
            emailField
            PhoneField(symbol: "lock", placeholder: "Choose a password", text: $auth.password, secure: true,
                       contentType: .newPassword, focus: $focus, field: .password) { focus = .confirmation }
            PhoneField(symbol: "lock.shield", placeholder: "Repeat password", text: $auth.passwordConfirmation, secure: true,
                       contentType: .newPassword, focus: $focus, field: .confirmation, submit: submitSignUp)
            PasswordRules(password: auth.password, confirmation: auth.passwordConfirmation)
            primary("Create account", symbol: "person.badge.plus", enabled: canCreateAccount, action: submitSignUp)
            backToSignIn
        case .forgotPassword:
            emailField
            primary("Send code", symbol: "envelope", enabled: !auth.email.isEmpty, action: submitResetRequest)
            backToSignIn
        case .confirmSignUp:
            codeField(submit: submitConfirmation)
            primary("Confirm email", symbol: "checkmark", enabled: AuthModel.isCompleteCode(auth.code),
                    action: submitConfirmation)
            HStack {
                Button("Different email") { auth.show(.createAccount) }.buttonStyle(LinkStyle())
                Spacer()
                ResendControl(auth: auth)
            }
            .frame(minHeight: 44)
        case .resetPassword:
            codeField { focus = .newPassword }
            PhoneField(symbol: "lock", placeholder: "New password", text: $auth.newPassword, secure: true,
                       contentType: .newPassword, focus: $focus, field: .newPassword) { focus = .confirmation }
            PhoneField(symbol: "lock.shield", placeholder: "Repeat password", text: $auth.passwordConfirmation, secure: true,
                       contentType: .newPassword, focus: $focus, field: .confirmation, submit: submitReset)
            PasswordRules(password: auth.newPassword, confirmation: auth.passwordConfirmation)
            primary("Save new password", symbol: "checkmark", enabled: canReset, action: submitReset)
            HStack {
                backToSignIn
                Spacer()
                ResendControl(auth: auth)
            }
            .frame(minHeight: 44)
        }
    }

    private var emailField: some View {
        PhoneField(symbol: "envelope", placeholder: "Email", text: $auth.email, contentType: .username,
                   keyboard: .emailAddress, focus: $focus, field: .email) {
            if auth.authStep == .forgotPassword { submitResetRequest() } else { focus = .password }
        }
    }

    private func codeField(submit: @escaping () -> Void) -> some View {
        PhoneField(symbol: "number", placeholder: "Code from the email", text: $auth.code, contentType: .oneTimeCode,
                   keyboard: .numberPad, monospaced: true, focus: $focus, field: .code, submit: submit)
            .onChange(of: auth.code) { _, value in
                let digits = String(value.filter(\.isNumber).filter(\.isASCII).prefix(AuthModel.codeLengths.upperBound))
                if digits != value { auth.code = digits }
            }
            .accessibilityHint("\(AuthModel.codeLengths.lowerBound) to \(AuthModel.codeLengths.upperBound) digits")
    }

    private func primary(_ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if auth.isBusy { ProgressView().tint(.white) }
                Label(title, systemImage: symbol)
            }
        }
        .buttonStyle(PrimaryPillStyle(height: Theme.Size.largePill, font: Theme.Fonts.appName))
        .disabled(!enabled || auth.isBusy)
        .accessibilityIdentifier("auth-primary")
    }

    private var backToSignIn: some View {
        Button { auth.show(.signIn) } label: { Label("Back to sign in", systemImage: "chevron.left") }
            .buttonStyle(LinkStyle())
    }

    private var canCreateAccount: Bool {
        !auth.email.isEmpty && AuthModel.passwordProblem(auth.password) == nil && auth.password == auth.passwordConfirmation
    }

    private var canReset: Bool {
        AuthModel.isCompleteCode(auth.code) && AuthModel.passwordProblem(auth.newPassword) == nil
            && auth.newPassword == auth.passwordConfirmation
    }

    private func submitSignIn() {
        guard !auth.email.isEmpty, !auth.password.isEmpty else { return }
        Task { await auth.signIn() }
    }

    private func submitSignUp() {
        guard canCreateAccount else { return }
        Task { await auth.signUp(email: auth.email, password: auth.password) }
    }

    private func submitResetRequest() {
        guard !auth.email.isEmpty else { return }
        Task { await auth.requestPasswordReset(email: auth.email) }
    }

    private func submitConfirmation() {
        guard AuthModel.isCompleteCode(auth.code) else { return }
        Task { await auth.confirmSignUp(code: auth.code) }
    }

    private func submitReset() {
        guard canReset else { return }
        Task { await auth.completePasswordReset(code: auth.code, newPassword: auth.newPassword) }
    }
}

extension AuthStep {
    var title: String {
        switch self {
        case .signIn: "Sign in"
        case .createAccount: "Create account"
        case .forgotPassword: "Reset password"
        case .confirmSignUp: "Enter the code"
        case .resetPassword: "New password"
        }
    }

    var subtitle: String {
        switch self {
        case .signIn: "Use your Daily Challenge email and password. The same account works on your iPhone and your Macs."
        case .createAccount: "Choose the email and password you'll use on every device. We'll email you a code to confirm it's yours."
        case .forgotPassword: "Enter the email you signed up with and we'll send you a code."
        case .confirmSignUp(let email), .resetPassword(let email):
            "We sent a code to \(email). Codes expire, so use the one in the newest email. Check your spam folder if it hasn't arrived."
        }
    }

    var symbol: String {
        switch self {
        case .signIn: "cloud"
        case .createAccount: "person.badge.plus"
        case .forgotPassword: "key"
        case .confirmSignUp: "envelope"
        case .resetPassword: "lock"
        }
    }

    var isCode: Bool {
        switch self {
        case .confirmSignUp, .resetPassword: true
        case .signIn, .createAccount, .forgotPassword: false
        }
    }
}

/// A 46 pt capsule field with a leading icon and a focus ring, as on the Mac.
struct PhoneField: View {
    let symbol: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var monospaced = false
    let focus: FocusState<AuthScreen.Field?>.Binding
    let field: AuthScreen.Field
    var submit: () -> Void = {}
    @State private var reveal = false

    var body: some View {
        let focused = focus.wrappedValue == field
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                .foregroundStyle(focused ? Theme.focus : Theme.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Group {
                if secure && !reveal {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(monospaced ? Theme.Fonts.field.monospaced() : Theme.Fonts.field)
            .foregroundStyle(Theme.textPrimary)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused(focus, equals: field)
            .onSubmit(submit)
            .accessibilityLabel(placeholder)
            if secure {
                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(reveal ? "Hide password" : "Show password")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, secure ? 4 : 16)
        .frame(minHeight: Theme.Size.field)
        .background(Capsule(style: .circular).fill(Theme.fieldFill))
        .overlay(Capsule(style: .circular).strokeBorder(focused ? Theme.focus : Theme.controlFill, lineWidth: focused ? 1.5 : 1))
        .background { if focused { Capsule(style: .circular).stroke(Theme.focusHalo, lineWidth: 6) } }
        .contentShape(Capsule(style: .circular))
        .onTapGesture { focus.wrappedValue = field }
    }
}

/// 10+ · Aa · 0–9 · Match: each chip turns green with a check as its rule is met.
struct PasswordRules: View {
    let password: String
    let confirmation: String

    var body: some View {
        let rules: [(String, String, Bool)] = [
            ("10+", "at least \(AuthModel.minimumPasswordLength) characters", password.count >= AuthModel.minimumPasswordLength),
            ("Aa", "a letter", password.contains { $0.isASCII && $0.isLetter }),
            ("0–9", "a number", password.contains { $0.isASCII && $0.isNumber }),
            ("Match", "both passwords match", !confirmation.isEmpty && password == confirmation)
        ]
        HStack(spacing: 8) {
            ForEach(rules, id: \.0) { text, _, met in
                HStack(spacing: 5) {
                    if met {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                    } else {
                        Circle().fill(Theme.textTertiary).frame(width: 6, height: 6)
                    }
                    Text(text).font(Theme.Fonts.badge)
                }
                .foregroundStyle(met ? Theme.doneText : Theme.textSecondary)
                .padding(.horizontal, 10).frame(minHeight: 26)
                .background(Capsule(style: .circular).fill(met ? Theme.doneTint : Theme.controlFill))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Password rules: " + rules.map { "\($0.1), \($0.2 ? "met" : "not met")" }.joined(separator: "; "))
    }
}

/// Shows the wait instead of a dead button while the 60-second resend limit applies.
struct ResendControl: View {
    let auth: AuthModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = auth.resendWait(at: context.date)
            if wait > 0 {
                Label("\(wait)s", systemImage: "arrow.clockwise")
                    .font(Theme.Fonts.pill).monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 14).frame(minHeight: 34)
                    .background(Capsule(style: .circular).fill(Theme.controlFill))
                    .accessibilityLabel("You can request a new code in \(wait) seconds")
            } else {
                Button { Task { await auth.resendCode() } } label: { Label("Resend", systemImage: "arrow.clockwise") }
                    .buttonStyle(TintedPillStyle(height: 34, foreground: Theme.accentText))
                    .accessibilityLabel("Resend code")
            }
        }
    }
}
