import SwiftUI

enum CatharsiaStyle {
    static let canvas = Color(red: 0.976, green: 0.965, blue: 0.992)
    static let panel = Color.white
    static let panelRaised = Color(red: 0.941, green: 0.918, blue: 0.976)
    static let ink = Color(red: 0.157, green: 0.125, blue: 0.220)
    static let muted = Color(red: 0.388, green: 0.357, blue: 0.455)
    static let violet = Color(red: 0.392, green: 0.251, blue: 0.694)
    static let coral = Color(red: 0.804, green: 0.216, blue: 0.333)
    static let aqua = Color(red: 0.043, green: 0.443, blue: 0.416)
    static let butter = Color(red: 0.545, green: 0.369, blue: 0.020)
    static let action = violet

    static let atmosphere = LinearGradient(
        colors: [Color(red: 0.950, green: 0.928, blue: 0.988), canvas, Color(red: 0.920, green: 0.960, blue: 0.955)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct BrainMark: View {
    var size: CGFloat = 30

    var body: some View {
        Image("CatharsiaMark")
            .resizable()
            .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct BrainGlowMark: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Ellipse()
                .fill(CatharsiaStyle.violet.opacity(0.20))
                .frame(width: size * 1.75, height: size * 1.25)
                .blur(radius: size * 0.30)
                .offset(x: -size * 0.10, y: -size * 0.04)
            Ellipse()
                .fill(CatharsiaStyle.aqua.opacity(0.17))
                .frame(width: size * 1.55, height: size * 1.10)
                .blur(radius: size * 0.27)
                .offset(x: size * 0.12, y: size * 0.10)
            BrainMark(size: size)
                .shadow(color: CatharsiaStyle.violet.opacity(0.13), radius: size * 0.10, y: size * 0.04)
        }
        .frame(width: size * 2, height: size * 1.8)
        .accessibilityHidden(true)
    }
}

struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(CatharsiaStyle.aqua)
    }
}

struct ContentCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CatharsiaStyle.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CatharsiaStyle.ink.opacity(0.07), lineWidth: 1))
    }
}
