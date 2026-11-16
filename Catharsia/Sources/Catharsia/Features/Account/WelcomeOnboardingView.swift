import SwiftUI

struct WelcomeOnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    Image("CatharsiaMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 116, height: 116)
                        .accessibilityLabel("Catharsia abstract brain mark")

                    Text("HOPEFUL DISCOVERY")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(CatharsiaStyle.aqua)
                        .padding(.top, 34)

                    Text("A gentler way to\nfind support")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .tracking(-1.1)
                        .foregroundStyle(CatharsiaStyle.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 13)

                    Text("Explore therapist stories, group gatherings, practice events, and useful resources.")
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(CatharsiaStyle.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 330)
                        .padding(.top, 14)

                    Label("Browse freely. No account needed to explore.", systemImage: "sparkle")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CatharsiaStyle.aqua)
                        .multilineTextAlignment(.center)
                        .padding(.top, 24)

                    Spacer(minLength: 36)

                    Button(action: onContinue) {
                        Text("Start exploring")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(CatharsiaStyle.violet, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the therapist discovery feed")
                    .padding(.bottom, 18)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .background(CatharsiaStyle.canvas.ignoresSafeArea())
        }
        .preferredColorScheme(.light)
    }
}
