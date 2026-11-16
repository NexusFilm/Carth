import SwiftUI

struct SafetySupportView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(CatharsiaStyle.aqua)
                    .accessibilityHidden(true)

                Text("Support when you need it")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(CatharsiaStyle.ink)

                Text("Catharsia shares general education and is not an emergency service. If you or someone else may be in immediate danger, contact local emergency services.")
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(CatharsiaStyle.muted)

                ContentCard {
                    Eyebrow(text: "United States")
                    Text("988 Suicide & Crisis Lifeline")
                        .font(.headline)
                        .padding(.top, 5)
                    Text("Call or text 988 to reach a trained crisis counselor. If texting or calling is not safe for you, use the chat option when available.")
                        .font(.subheadline)
                        .foregroundStyle(CatharsiaStyle.muted)
                        .padding(.top, 5)
                    HStack(spacing: 12) {
                        Link(destination: URL(string: "tel:988")!) {
                            Label("Call 988", systemImage: "phone.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Link(destination: URL(string: "sms:988")!) {
                            Label("Text 988", systemImage: "message.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 12)
                    Link("More ways to get help", destination: URL(string: "https://988lifeline.org/get-help/")!)
                        .font(.footnote.weight(.medium))
                        .padding(.top, 8)
                }

                Text("If you are outside the United States, contact your local crisis line or emergency service.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
    }
}
