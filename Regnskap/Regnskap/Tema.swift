import SwiftUI
import UIKit

/// Farger og stil fra nettsiden (site/styles.css), så appen og tillerflaten.no ser like ut.
/// Fargene ligger i Assets.xcassets med egne varianter for mørk modus.
extension Color {
    /// Varm, lys bakgrunn (--bg)
    static let temaBakgrunn = Color("Bakgrunn")
    /// Kort og rader (--surface)
    static let temaFlate = Color("Flate")
    /// Mørk petrol fra toppen av nettsiden (--hero-bg)
    static let temaHero = Color("Hero")
    static let temaHeroTekst = Color("HeroTekst")
    static let temaHeroDempet = Color("HeroDempet")
    /// Lys fjellfarge fra logoen
    static let temaFjell = Color("Fjell")
    /// Svak aksentfarge (--accent-soft)
    static let temaAksentMyk = Color("AksentMyk")
}

extension Font {
    /// Overskriftsfont. Nettsiden bruker Fraunces; New York (systemets serif) ligner mest.
    static func tittel(_ stil: Font.TextStyle = .title2, vekt: Font.Weight = .semibold) -> Font {
        .system(stil, design: .serif, weight: vekt)
    }
}

enum Tema {
    /// Gir navigasjonslinjene serif-titler og samme bakgrunn som resten av appen.
    static func konfigurer() {
        func serif(_ stil: UIFont.TextStyle, vekt: UIFont.Weight) -> UIFont {
            let basis = UIFont.preferredFont(forTextStyle: stil)
            let medVekt = basis.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: vekt.rawValue]])
            let beskrivelse = medVekt.withDesign(.serif) ?? medVekt
            return UIFont(descriptor: beskrivelse, size: basis.pointSize)
        }

        let tekst = UIColor(named: "Hero") ?? .label
        let lysTekst = UIColor { $0.userInterfaceStyle == .dark ? UIColor(named: "HeroTekst") ?? .label : tekst }

        let utseende = UINavigationBarAppearance()
        utseende.configureWithDefaultBackground()
        utseende.largeTitleTextAttributes = [.font: serif(.largeTitle, vekt: .semibold), .foregroundColor: lysTekst]
        utseende.titleTextAttributes = [.font: serif(.headline, vekt: .semibold), .foregroundColor: lysTekst]

        let iToppen = UINavigationBarAppearance()
        iToppen.configureWithTransparentBackground()
        iToppen.largeTitleTextAttributes = utseende.largeTitleTextAttributes
        iToppen.titleTextAttributes = utseende.titleTextAttributes

        UINavigationBar.appearance().standardAppearance = utseende
        UINavigationBar.appearance().compactAppearance = utseende
        UINavigationBar.appearance().scrollEdgeAppearance = iToppen
    }
}

/// Den varme bakgrunnen fra nettsiden bak lister og skjemaer.
struct TemaBakgrunn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.temaBakgrunn.ignoresSafeArea())
    }
}

extension View {
    func temaBakgrunn() -> some View { modifier(TemaBakgrunn()) }
}

/// Fjellryggen nederst i toppen av nettsiden (samme punkter som SVG-en i site/index.html).
struct Fjellrygg: Shape {
    func path(in rect: CGRect) -> Path {
        let punkter: [(CGFloat, CGFloat)] = [
            (0, 110), (180, 50), (320, 95), (470, 20), (640, 100), (780, 60),
            (930, 115), (1100, 35), (1260, 90), (1440, 55),
        ]
        let sx = rect.width / 1440
        let sy = rect.height / 160
        var sti = Path()
        sti.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (x, y) in punkter {
            sti.addLine(to: CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy))
        }
        sti.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        sti.closeSubpath()
        return sti
    }
}

/// Logoen: to fjelltopper, som i favicon.svg.
struct Logomerke: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 32
        var sti = Path()
        sti.move(to: CGPoint(x: 3 * s, y: 26 * s))
        sti.addLine(to: CGPoint(x: 12 * s, y: 10 * s))
        sti.addLine(to: CGPoint(x: 17 * s, y: 18 * s))
        sti.addLine(to: CGPoint(x: 21 * s, y: 12 * s))
        sti.addLine(to: CGPoint(x: 29 * s, y: 26 * s))
        sti.closeSubpath()
        return sti
    }
}

/// Mørkt kort med fjellrygg, som toppen av nettsiden. Brukes øverst på Oversikt.
struct HeroKort<Innhold: View>: View {
    @ViewBuilder var innhold: Innhold

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            innhold
        }
        .foregroundStyle(Color.temaHeroTekst)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 44)
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                Color.temaHero
                Fjellrygg()
                    .fill(Color.temaBakgrunn.opacity(0.12))
                    .frame(height: 40)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
