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

/// Signed-out surface: sign in, create an account, or reset a password with an emailed code.
struct AuthView: View {
    @Bindable var model: ProofModel
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, password, confirmation, code, newPassword }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Guidance and errors sit above the form, where they are read first.
            if let notice = model.notice {
                Label(notice, systemImage: model.authStep.isCodeStep ? "envelope.badge" : "info.circle")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
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

    private var firstField: Field {
        switch model.authStep {
        case .signIn: model.email.isEmpty ? .email : .password
        case .createAccount, .forgotPassword: .email
        case .confirmSignUp, .resetPassword: .code
        }
    }

    // MARK: Modes

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 10) {
            emailField
            SecureField("Password", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .onSubmit(submitSignIn)
            HStack {
                Button("Sign in", action: submitSignIn)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.email.isEmpty || model.password.isEmpty)
                Spacer()
                Button("Forgot password?") { model.show(.forgotPassword) }
                    .buttonStyle(.link).font(.caption)
            }
            Divider()
            HStack(spacing: 4) {
                Text("New here?").font(.caption).foregroundStyle(.secondary)
                Button("Create an account") { model.show(.createAccount) }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }

    private var createAccount: some View {
        VStack(alignment: .leading, spacing: 10) {
            emailField
            SecureField("Choose a password", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
                .focused($focus, equals: .password)
                .onSubmit { focus = .confirmation }
            SecureField("Type the password again", text: $model.passwordConfirmation)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
                .focused($focus, equals: .confirmation)
                .onSubmit(submitSignUp)
            passwordHint(model.password, model.passwordConfirmation)
            HStack {
                Button("Create account", action: submitSignUp)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreateAccount)
                Spacer()
                backToSignIn
            }
        }
    }

    private var forgotPassword: some View {
        VStack(alignment: .leading, spacing: 10) {
            emailField
            HStack {
                Button("Send code", action: submitResetRequest)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.email.isEmpty)
                Spacer()
                backToSignIn
            }
        }
    }

    private func confirmSignUp(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sentTo(address)
            codeField.onSubmit(submitConfirmation)
            HStack {
                Button("Confirm", action: submitConfirmation)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ProofModel.isCompleteCode(model.code))
                Spacer()
                resendControl
            }
            Divider()
            HStack(spacing: 12) {
                Button("Use a different email") { model.show(.createAccount) }
                    .buttonStyle(.link).font(.caption)
                backToSignIn
            }
        }
    }

    private func resetPassword(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sentTo(address)
            codeField.onSubmit { focus = .newPassword }
            SecureField("New password", text: $model.newPassword)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
                .focused($focus, equals: .newPassword)
                .onSubmit { focus = .confirmation }
            SecureField("Type the new password again", text: $model.passwordConfirmation)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
                .focused($focus, equals: .confirmation)
                .onSubmit(submitReset)
            passwordHint(model.newPassword, model.passwordConfirmation)
            HStack {
                Button("Save password and sign in", action: submitReset)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canReset)
                Spacer()
                resendControl
            }
            Divider()
            HStack(spacing: 12) {
                Button("Use a different email") { model.show(.forgotPassword) }
                    .buttonStyle(.link).font(.caption)
                backToSignIn
            }
        }
    }

    // MARK: Pieces

    private var emailField: some View {
        TextField("Email", text: $model.email)
            .textFieldStyle(.roundedBorder)
            .textContentType(.username)
            .focused($focus, equals: .email)
            .onSubmit {
                if model.authStep == .forgotPassword { submitResetRequest() } else { focus = .password }
            }
    }

    private var codeField: some View {
        TextField("Code from the email", text: $model.code)
            .textFieldStyle(.roundedBorder)
            .textContentType(.oneTimeCode)
            .font(.title3.monospacedDigit())
            .focused($focus, equals: .code)
            .accessibilityLabel("Code from the email")
            .onChange(of: model.code) { _, value in
                let digits = String(value.filter(\.isNumber).filter(\.isASCII).prefix(ProofModel.codeLengths.upperBound))
                if digits != value { model.code = digits }
            }
    }

    @ViewBuilder
    private func sentTo(_ address: String) -> some View {
        // The notice already names the address whenever a code was just sent.
        if model.notice == nil {
            Label {
                Text("Code sent to **\(address)**").textSelection(.enabled)
            } icon: {
                Image(systemName: "envelope.badge")
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
        }
    }

    /// Shows the wait instead of a dead button while the 60-second resend limit applies.
    private var resendControl: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = model.resendWait(at: context.date)
            if wait > 0 {
                Text("Resend code in \(wait)s")
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("You can request a new code in \(wait) seconds")
            } else {
                Button("Resend code") { Task { await model.resendCode() } }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }

    private var backToSignIn: some View {
        Button("Back to sign in") { model.show(.signIn) }
            .buttonStyle(.link).font(.caption)
    }

    @ViewBuilder
    private func passwordHint(_ password: String, _ confirmation: String) -> some View {
        if !confirmation.isEmpty, password != confirmation {
            Text("The passwords don't match yet.").font(.caption).foregroundStyle(.orange)
        } else if let problem = ProofModel.passwordProblem(password) {
            Text(problem).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
