import AuthenticationServices
import SwiftUI

struct AccountAccessView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var isRegistering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Your account")
                        Text(isRegistering ? "Create your account" : "Welcome back")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.ink)
                        Text("Explore is open to everyone. Sign in only to like, comment, or save posts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button {
                        Task { await session.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 12) {
                            Image("GoogleG")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Continue with Google")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(red: 0.122, green: 0.122, blue: 0.122))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(red: 0.455, green: 0.467, blue: 0.455), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Continue with Google")
                    .disabled(session.isWorking)

                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = session.prepareAppleSignIn()
                    } onCompletion: { result in
                        Task { await session.completeAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.whiteOutline)
                    .frame(height: 48)
                    .disabled(session.isWorking)
                } header: {
                    Text(isRegistering ? "Continue with" : "Sign in with")
                } footer: {
                    Text("Or use your email")
                }

                if isRegistering {
                    Section("Your name") {
                        TextField("Name", text: $name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section("Email and password") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(isRegistering ? .newPassword : .password)
                }

                if let message = session.accountMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        Task {
                            if isRegistering {
                                await session.register(name: name, email: email, password: password)
                            } else {
                                await session.signIn(email: email, password: password)
                            }
                            if session.isSignedIn { dismiss() }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if session.isWorking {
                                ProgressView()
                            } else {
                                Text(isRegistering ? "Create account" : "Sign in")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(session.isWorking || !isFormValid)
                }

                Section {
                    Button(isRegistering ? "I already have an account" : "Create an account") {
                        isRegistering.toggle()
                        session.accountMessage = nil
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(Color(uiColor: .secondarySystemGroupedBackground), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
        .preferredColorScheme(.light)
    }

    private var isFormValid: Bool {
        email.contains("@") && password.count >= 8 && (!isRegistering || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}
