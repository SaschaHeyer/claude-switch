import SwiftUI

/// Bold, like coepi.eu and angelschein-lernen.de: one loud color, ink type,
/// 2px ink outlines, pill buttons and hard offset shadows.
enum Brand {
    static let tangerine = Color(hex: 0xFF6B2C)
    static let paper = Color(hex: 0xFFF5EC)
    static let cream = Color(hex: 0xFFE7D3)
    static let ink = Color(hex: 0x17120E)
    static let inkSoft = Color(hex: 0x5C4D41)
    static let line = Color(hex: 0x17120E).opacity(0.14)
    static let white = Color.white
    static let go = Color(hex: 0x1F9D63)
    static let border: CGFloat = 2
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .custom("BricolageGrotesque-ExtraBold", size: size) }
    static func displayLight(_ size: CGFloat) -> Font { .custom("BricolageGrotesque-Light", size: size) }
    static func displaySemi(_ size: CGFloat) -> Font { .custom("BricolageGrotesque-SemiBold", size: size) }
    static func body(_ size: CGFloat = 14) -> Font { .custom("Figtree-Medium", size: size) }
    static func bodyBold(_ size: CGFloat = 14) -> Font { .custom("Figtree-Bold", size: size) }
    static func mono(_ size: CGFloat = 11) -> Font { .custom("IBMPlexMono-Medium", size: size) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Pieces

/// White card with an ink outline sitting on a hard ink shadow.
struct InkCard: ViewModifier {
    var fill: Color = Brand.white
    var radius: CGFloat = 22
    var shadow: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Brand.ink, lineWidth: Brand.border))
            .background(RoundedRectangle(cornerRadius: radius).fill(Brand.ink).offset(y: shadow))
    }
}

extension View {
    func inkCard(fill: Color = Brand.white, radius: CGFloat = 22, shadow: CGFloat = 4) -> some View {
        modifier(InkCard(fill: fill, radius: radius, shadow: shadow))
    }
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case ink, ghost, color(Color, Color) }
    var kind: Kind = .ink
    var size: CGFloat = 14
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, size: size, fullWidth: fullWidth)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let kind: Kind
        let size: CGFloat
        let fullWidth: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var colors: (Color, Color) {
            switch kind {
            case .ink: (Brand.ink, Brand.paper)
            case .ghost: (hover ? Brand.white : .clear, Brand.ink)
            case .color(let bg, let fg): (bg, fg)
            }
        }

        var body: some View {
            configuration.label
                .font(.bodyBold(size))
                .foregroundStyle(colors.1)
                .padding(.horizontal, size * 1.3)
                .padding(.vertical, size * 0.78)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(Capsule().fill(colors.0))
                .overlay(Capsule().strokeBorder(Brand.ink, lineWidth: Brand.border))
                .contentShape(Capsule())
                .offset(y: configuration.isPressed ? 1 : (hover && enabled ? -2 : 0))
                .opacity(enabled ? 1 : 0.4)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hover)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hover = $0 }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var ink: PillButtonStyle { PillButtonStyle() }
    static var ghost: PillButtonStyle { PillButtonStyle(kind: .ghost) }
    static func pill(_ kind: PillButtonStyle.Kind = .ink, size: CGFloat = 14, fullWidth: Bool = false) -> PillButtonStyle {
        PillButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

/// The profile's letter on its color, like the Dock icon.
struct ProfileBadge: View {
    let letter: String
    let color: ProfileColor
    var size: CGFloat = 36

    var body: some View {
        Text(letter)
            .font(.display(size * 0.56))
            .foregroundStyle(color.onColor)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28).fill(color.color))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(Brand.ink, lineWidth: Brand.border))
            .background(RoundedRectangle(cornerRadius: size * 0.28).fill(Brand.ink).offset(y: size * 0.07))
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = Brand.inkSoft
    init(_ text: String, color: Color = Brand.inkSoft) { self.text = text; self.color = color }

    var body: some View {
        Text(text.uppercased()).font(.mono(10.5)).tracking(1.4).foregroundStyle(color)
    }
}

struct Chip: View {
    let text: String
    var fill: Color = Brand.white
    var fg: Color = Brand.ink
    var icon: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.mono(10))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 3.5)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(Brand.ink, lineWidth: 1.5))
    }
}

/// Green dot that breathes while a profile's Claude is open.
struct LiveDot: View {
    var size: CGFloat = 9
    @State private var pulse = false

    var body: some View {
        Circle().fill(Brand.go)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Brand.ink, lineWidth: 1.5))
            .background(
                Circle().fill(Brand.go.opacity(0.35))
                    .scaleEffect(pulse ? 2.1 : 1)
                    .opacity(pulse ? 0 : 1)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

enum Fonts {
    /// ATSApplicationFontsPath registers them too; this covers `swift run` and previews.
    static func register() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
}
