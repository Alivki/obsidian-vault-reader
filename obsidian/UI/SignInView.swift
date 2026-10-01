import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            VStack(spacing: 18) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Shad.border.opacity(0.6), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("Obsidian")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Shad.foreground)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(Shad.mutedForeground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if case .awaitingUser(let code) = model.auth.phase {
                Button {
                    copy(code.userCode)
                } label: {
                    CodeBoxes(code: code.userCode)
                }
                .buttonStyle(.plain)
                .padding(.top, 36)
                .accessibilityHint("Copies the code")

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(code.expiresAt.timeIntervalSince(context.date)))
                    HStack(spacing: 6) {
                        if copied {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Shad.success)
                            Text("Code copied")
                                .foregroundStyle(Shad.foreground)
                        } else {
                            Text("Tap the code to copy · expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                                .foregroundStyle(Shad.mutedForeground)
                                .monospacedDigit()
                        }
                    }
                    .font(.footnote)
                    .animation(.easeOut(duration: 0.15), value: copied)
                }
                .padding(.top, 14)
            }

            Spacer(minLength: 32)

            VStack(spacing: 12) {
                actions
            }
            .frame(maxWidth: 400)

            Text("Read-only access. Your token stays in this device's Keychain and is only sent to GitHub.")
                .font(.footnote)
                .foregroundStyle(Shad.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, Shad.isMac ? 32 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Shad.background.ignoresSafeArea())
    }

    private func copy(_ code: String) {
        Clipboard.copy(code)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private var subtitle: String {
        if case .awaitingUser = model.auth.phase {
            return "Enter this code on GitHub to finish signing in."
        }
        return "Read your Obsidian notes from\n\(AppConfig.repoFullName)"
    }

    @ViewBuilder private var actions: some View {
        switch model.auth.phase {
        case .awaitingUser(let code):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval on GitHub…")
                    .font(.footnote)
                    .foregroundStyle(Shad.mutedForeground)
            }
            .padding(.bottom, 4)
            Button("Open GitHub") {
                copy(code.userCode)
                openURL(AppConfig.deviceVerificationURL)
            }
            .buttonStyle(.shad(.primary, size: .lg, fullWidth: true))
            Button("Cancel") {
                model.auth.cancelSignIn()
                copied = false
            }
            .buttonStyle(.shad(.ghost, size: .md, fullWidth: true))
            .foregroundStyle(Shad.mutedForeground)

        case .requestingCode, .signedIn:
            Button {} label: {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Shad.primaryForeground)
                    Text("Connecting…")
                }
            }
            .buttonStyle(.shad(.primary, size: .lg, fullWidth: true))
            .disabled(true)

        case .signedOut(let message):
            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Shad.destructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
            Button("Continue with GitHub") { model.auth.startSignIn() }
                .buttonStyle(.shad(.primary, size: .lg, fullWidth: true))
        }
    }
}

private struct CodeBoxes: View {
    let code: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(code.split(separator: "-").enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Text("–").font(.title2).foregroundStyle(Shad.mutedForeground)
                }
                HStack(spacing: 6) {
                    ForEach(Array(group.enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Shad.foreground)
                            .frame(width: 34, height: 46)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Shad.searchFill))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
    }
}
