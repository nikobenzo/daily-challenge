import ChallengeSyncKit
import SwiftUI

extension AuthStep {
    var title: String {
        switch self {
        case .signIn: "Sign in"
        case .createAccount: "Create account"
        case .forgotPassword: "Reset password"
        case .confirmSignUp: "Confirm your email"
        case .resetPassword: "Choose a new password"
        }
    }

    var subtitle: String {
        switch self {
        case .signIn: "Use your Daily Challenge email and password. The same account works on all your Macs."
        case .createAccount: "Choose the email and password you'll use on every Mac. We'll email you a code to confirm it's yours."
        case .forgotPassword: "Enter the email you signed up with and we'll send you a code."
        case .confirmSignUp, .resetPassword: "Codes expire, so use the one in the newest email. Check your spam folder if it hasn't arrived."
        }
    }

    var isCodeStep: Bool {
        switch self {
        case .confirmSignUp, .resetPassword: true
        case .signIn, .createAccount, .forgotPassword: false
        }
    }
}

extension AuthStep {
    /// The hero title on the redesigned auth screens.
    var heroTitle: String {
        switch self {
        case .signIn: "Sign in"
        case .createAccount: "Create account"
        case .forgotPassword: "Reset password"
        case .confirmSignUp: "Enter the code"
        case .resetPassword: "New password"
        }
    }

    var heroSymbol: String {
        switch self {
        case .signIn: "cloud"
        case .createAccount: "person.badge.plus"
        case .forgotPassword: "key"
        case .confirmSignUp: "envelope"
        case .resetPassword: "lock"
        }
    }
}

/// The signed-out sheet body: the auth form, then device settings below a hairline.
struct ProofView: View {
    @Bindable var model: ProofModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.configurationReady {
                    AuthView(model: model)
                } else {
                    VStack(spacing: 12) {
                        AuthHero(step: .signIn, help: model.authStep.subtitle)
                        Text(model.status).font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                        if let error = model.errorMessage { FieldError(text: error) }
                    }
                }
            }
            .padding(.horizontal, Theme.Size.sectionHorizontal)
            .padding(.top, Theme.Space.xl)
            .padding(.bottom, Theme.Space.l)
            HairlineDivider()
            VStack(spacing: 4) {
                AppearanceSettings()
                LaunchAtLoginSettings()
            }
            .padding(.horizontal, Theme.Size.sectionHorizontal)
            .padding(.vertical, Theme.Space.s)
        }
    }
}

/// Round gradient icon and the screen title; the step's guidance is the tooltip.
struct AuthHero: View {
    let step: AuthStep
    var dot = false
    var help: String?

    var body: some View {
        VStack(spacing: 14) {
            HeroIcon(symbol: step.heroSymbol, dot: dot)
            Text(step.heroTitle).font(Theme.Fonts.screenTitle).tracking(Theme.Tracking.screenTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(help ?? "")
        }
        .frame(maxWidth: .infinity)
        .help(help ?? step.title)
    }
}

/// Signed-out surface: sign in, create an account, or reset a password with an emailed code.
struct AuthView: View {
    @Bindable var model: ProofModel
    @FocusState private var focus: Field?

    enum Field: Hashable { case email, password, confirmation, code, newPassword }

    var body: some View {
        VStack(spacing: 12) {
            AuthHero(step: model.authStep, dot: model.authStep.isCodeStep && model.authStep != .resetPassword(email: address),
                     help: model.authStep.subtitle)
                .padding(.bottom, 4)
            // Guidance and errors sit above the form, where they are read first.
            if let notice = model.notice {
                Label(notice, systemImage: model.authStep.isCodeStep ? "envelope.badge" : "info.circle")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityLabel("Error: \(error)")
            }
            switch model.authStep {
            case .signIn: signIn
            case .createAccount: createAccount
            case .forgotPassword: forgotPassword
            case .confirmSignUp(let address): confirmSignUp(address)
            case .resetPassword(let address): resetPassword(address)
            }
        }
        .disabled(model.isBusy)
        .onAppear { focus = firstField }
        .onChange(of: model.authStep) { _, _ in focus = firstField }
    }

    private var address: String {
        switch model.authStep {
        case .confirmSignUp(let email), .resetPassword(let email): email
        default: ""
        }
    }

    private var firstField: Field {
        switch model.authStep {
        case .signIn: model.email.isEmpty ? .email : .password
        case .createAccount, .forgotPassword: .email
        case .confirmSignUp, .resetPassword: .code
        }
    }

    // MARK: Modes

    private var signIn: some View {
        VStack(spacing: 12) {
            emailField
            GlassField(symbol: "lock", placeholder: "Password", text: $model.password, secure: true,
                       contentType: .password, focus: $focus, equals: .password, onSubmit: submitSignIn)
            cta("Sign in", trailing: "arrow.right", action: submitSignIn)
                .disabled(model.email.isEmpty || model.password.isEmpty)
            HStack {
                Button { model.show(.createAccount) } label: { Label("Create account", systemImage: "person.badge.plus") }
                    .buttonStyle(LinkStyle())
                Spacer()
                Button { model.show(.forgotPassword) } label: { Label("Forgot password?", systemImage: "questionmark.circle") }
                    .buttonStyle(LinkStyle())
            }
            .padding(.horizontal, 6)
        }
    }

    private var createAccount: some View {
        VStack(spacing: 12) {
            emailField
            GlassField(symbol: "lock", placeholder: "Choose a password", text: $model.password, secure: true,
                       contentType: .newPassword, focus: $focus, equals: .password) { focus = .confirmation }
            RuleChips(password: model.password, confirmation: model.passwordConfirmation)
            GlassField(symbol: "lock.shield", placeholder: "Repeat password", text: $model.passwordConfirmation,
                       secure: true, invalid: mismatch(model.password), contentType: .newPassword,
                       focus: $focus, equals: .confirmation, onSubmit: submitSignUp)
            if mismatch(model.password) { FieldError(text: "The passwords don't match yet.") }
            cta("Create account", trailing: "arrow.right", action: submitSignUp)
                .disabled(!canCreateAccount)
            backToSignIn
        }
    }

    private var forgotPassword: some View {
        VStack(spacing: 12) {
            emailField
            cta("Send code", trailing: "paperplane", action: submitResetRequest)
                .disabled(model.email.isEmpty)
            backToSignIn
        }
    }

    private func confirmSignUp(_ address: String) -> some View {
        VStack(spacing: 12) {
            sentTo(address)
            CodeBoxes(code: $model.code, focus: $focus, onSubmit: submitConfirmation)
            codeRule
            cta("Verify", trailing: "checkmark", action: submitConfirmation)
                .disabled(!ProofModel.isCompleteCode(model.code))
            HStack {
                Button { model.show(.createAccount) } label: { Label("Different email", systemImage: "chevron.left") }
                    .buttonStyle(LinkStyle())
                    .help("Use a different email")
                Spacer()
                resendControl
            }
            .padding(.horizontal, 6)
        }
    }

    private func resetPassword(_ address: String) -> some View {
        VStack(spacing: 12) {
            stepChips
            GlassField(symbol: "envelope", placeholder: "Code from the email", text: $model.code,
                       valid: ProofModel.isCompleteCode(model.code), monospaced: true, contentType: .oneTimeCode,
                       focus: $focus, equals: .code) { focus = .newPassword }
                .accessibilityLabel("Code from the email")
                .help("Code sent to \(address). \(ProofModel.codeLengths.lowerBound)–\(ProofModel.codeLengths.upperBound) digits.")
                .onChange(of: model.code) { _, value in filterCode(value) }
            GlassField(symbol: "lock", placeholder: "New password", text: $model.newPassword, secure: true,
                       contentType: .newPassword, focus: $focus, equals: .newPassword) { focus = .confirmation }
            GlassField(symbol: "lock.shield", placeholder: "Repeat password", text: $model.passwordConfirmation,
                       secure: true, invalid: mismatch(model.newPassword), contentType: .newPassword,
                       focus: $focus, equals: .confirmation, onSubmit: submitReset)
            if mismatch(model.newPassword) { FieldError(text: "The passwords don't match yet.") }
            RuleChips(password: model.newPassword, confirmation: model.passwordConfirmation)
            cta("Save and sign in", action: submitReset)
                .disabled(!canReset)
            HStack {
                backToSignIn
                Spacer()
                resendControl
            }
            .padding(.horizontal, 6)
        }
    }

    // MARK: Pieces

    private var emailField: some View {
        GlassField(symbol: "envelope", placeholder: "Email", text: $model.email, contentType: .username,
                   focus: $focus, equals: .email) {
            if model.authStep == .forgotPassword { submitResetRequest() } else { focus = .password }
        }
    }

    private func cta(_ title: String, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if model.isBusy {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let trailing {
                    Image(systemName: trailing).font(.system(size: 14, weight: .bold))
                }
            }
        }
        .buttonStyle(PrimaryPillStyle(height: Theme.Size.largePill, font: Theme.Fonts.appName))
        .keyboardShortcut(.defaultAction)
    }

    private var codeRule: some View {
        Label("\(ProofModel.codeLengths.lowerBound)–\(ProofModel.codeLengths.upperBound) digits", systemImage: "clock")
            .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
            .help(model.authStep.subtitle)
    }

    private var stepChips: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").foregroundStyle(Theme.done)
                Image(systemName: "envelope")
            }
            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.doneText)
            .frame(width: 48, height: 26).background(Capsule(style: .circular).fill(Theme.doneTint))
            .help("Code sent to \(address)")
            Theme.hairline.frame(width: 16, height: 1.5)
            HStack(spacing: 6) {
                Text("2").font(Theme.Fonts.badge)
                Image(systemName: "key")
            }
            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textPrimary)
            .frame(width: 48, height: 26)
            .overlay(Capsule(style: .circular).strokeBorder(Theme.focus, lineWidth: 1.5))
            .help("Choose a new password")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step 2 of 2: choose a new password. Code sent to \(address).")
    }

    private func sentTo(_ address: String) -> some View {
        Text(address).font(Theme.Fonts.link).foregroundStyle(Theme.textSecondary)
            .lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule(style: .circular).fill(Theme.controlFill))
            .textSelection(.enabled)
            .help("Code sent to \(address)")
            .accessibilityLabel("Code sent to \(address)")
    }

    /// Shows the wait instead of a dead button while the 60-second resend limit applies.
    private var resendControl: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = model.resendWait(at: context.date)
            if wait > 0 {
                Label("\(wait)s", systemImage: "arrow.clockwise")
                    .font(Theme.Fonts.pill).monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(Capsule(style: .circular).fill(Theme.controlFill))
                    .help("Resend code in \(wait)s")
                    .accessibilityLabel("You can request a new code in \(wait) seconds")
            } else {
                Button { Task { await model.resendCode() } } label: { Label("Resend", systemImage: "arrow.clockwise") }
                    .buttonStyle(TintedPillStyle(height: 30, foreground: Theme.accentText))
                    .help("Resend code")
                    .accessibilityLabel("Resend code")
            }
        }
    }

    private var backToSignIn: some View {
        Button { model.show(.signIn) } label: { Label("Back to sign in", systemImage: "chevron.left") }
            .buttonStyle(LinkStyle())
    }

    private func mismatch(_ password: String) -> Bool {
        !model.passwordConfirmation.isEmpty && password != model.passwordConfirmation
    }

    private func filterCode(_ value: String) {
        let digits = String(value.filter(\.isNumber).filter(\.isASCII).prefix(ProofModel.codeLengths.upperBound))
        if digits != value { model.code = digits }
    }

    private var canCreateAccount: Bool {
        !model.email.isEmpty && ProofModel.passwordProblem(model.password) == nil
            && model.password == model.passwordConfirmation
    }

    private var canReset: Bool {
        ProofModel.isCompleteCode(model.code) && ProofModel.passwordProblem(model.newPassword) == nil
            && model.newPassword == model.passwordConfirmation
    }

    // MARK: Actions

    private func submitSignIn() {
        guard !model.email.isEmpty, !model.password.isEmpty else { return }
        Task { await model.signIn() }
    }

    private func submitSignUp() {
        guard canCreateAccount else { return }
        Task { await model.signUp(email: model.email, password: model.password) }
    }

    private func submitResetRequest() {
        guard !model.email.isEmpty else { return }
        Task { await model.requestPasswordReset(email: model.email) }
    }

    private func submitConfirmation() {
        guard ProofModel.isCompleteCode(model.code) else { return }
        Task { await model.confirmSignUp(code: model.code) }
    }

    private func submitReset() {
        guard canReset else { return }
        Task { await model.completePasswordReset(code: model.code, newPassword: model.newPassword) }
    }
}

/// One box per digit over a single real text field, so typing, pasting and one-time
/// code autofill behave like any field. 8 boxes, growing to 10 for longer codes.
struct CodeBoxes: View {
    @Binding var code: String
    let focus: FocusState<AuthView.Field?>.Binding
    var onSubmit: () -> Void

    var body: some View {
        let count = code.count >= 8 ? min(ProofModel.codeLengths.upperBound, code.count + 1) : 8
        let width = min(40, (380 - CGFloat(count - 1) * 8) / CGFloat(count))
        let focused = focus.wrappedValue == .code
        let digits = Array(code)
        ZStack {
            TextField("Code from the email", text: $code)
                .textFieldStyle(.plain)
                .textContentType(.oneTimeCode)
                .focused(focus, equals: .code)
                .onSubmit(onSubmit)
                .foregroundStyle(.clear)
                .tint(.clear)
                .opacity(0.02)
                .frame(height: 48)
                .accessibilityLabel("Code from the email")
                .onChange(of: code) { _, value in
                    let digits = String(value.filter(\.isNumber).filter(\.isASCII).prefix(ProofModel.codeLengths.upperBound))
                    if digits != value { code = digits }
                }
            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { index in
                    let current = focused && index == min(digits.count, count - 1)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.fieldFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(current ? Theme.focus : Theme.controlFill, lineWidth: current ? 1.5 : 1)
                        }
                        .background {
                            if current { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.focusHalo, lineWidth: 6) }
                        }
                        .overlay {
                            if index < digits.count {
                                Text(String(digits[index])).font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                            } else if current {
                                Theme.focus.frame(width: 1.5, height: 20)
                            }
                        }
                        .frame(width: width, height: 48)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = .code }
    }
}

/// 10+ · Aa · 0–9 · Match: each chip turns green with a check as its rule is met.
struct RuleChips: View {
    let password: String
    let confirmation: String

    var body: some View {
        let rules: [(String, String, Bool)] = [
            ("10+", "at least \(ProofModel.minimumPasswordLength) characters", password.count >= ProofModel.minimumPasswordLength),
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
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule(style: .circular).fill(met ? Theme.doneTint : Theme.controlFill))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .help(ProofModel.passwordRule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Password rules: " + rules.map { "\($0.1), \($0.2 ? "met" : "not met")" }.joined(separator: "; "))
    }
}
