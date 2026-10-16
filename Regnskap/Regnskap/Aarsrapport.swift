import SwiftUI
import UIKit

/// Regnskapet for ett år som PDF: sammendrag, tall til skattemeldingen og lister over alt som er ført.
enum Aarsrapport {
    struct Grunnlag {
        let aar: Int
        let bilag: [Bilag]
        let inntekter: [Inntekt]
        let driftsmidler: [Driftsmiddel]
        let turer: [Kjoretur]
        let fakturaer: [Faktura]
        let lonn: Double
        let mvaRegistrert: Bool
        let hjemmekontor: Bool
    }

    static func filnavn(aar: Int) -> String { "Regnskap \(aar).pdf" }

    /// Lager PDF-en og legger den i en midlertidig fil, klar til å vises eller deles.
    static func fil(_ g: Grunnlag) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filnavn(aar: g.aar))
        do {
            try data(g).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func data(_ g: Grunnlag) -> Data {
        let o = Aarsoversikt(aar: g.aar, bilag: g.bilag, inntekter: g.inntekter, driftsmidler: g.driftsmidler,
                             turer: g.turer, lonn: g.lonn, mvaRegistrert: g.mvaRegistrert, hjemmekontor: g.hjemmekontor)
        let n = Naeringsspesifikasjon(aar: g.aar, bilag: g.bilag, inntekter: g.inntekter, driftsmidler: g.driftsmidler,
                                      turer: g.turer, mvaRegistrert: g.mvaRegistrert, hjemmekontor: g.hjemmekontor)
        let bilag = g.bilag.filter { $0.dato.aar == g.aar }.sorted { $0.dato < $1.dato }
        let inntekter = g.inntekter.filter { $0.dato.aar == g.aar }.sorted { $0.dato < $1.dato }
        let fakturaer = g.fakturaer.filter { $0.nummer > 0 && $0.fakturadato.aar == g.aar }.sorted { $0.nummer < $1.nummer }

        let d = UserDefaults.standard
        let firma = Firma.lagretNavn
        let orgnr = Fakturering.orgnr(Firma.lagretOrgnr)
        let eier = d.string(forKey: Firma.eier) ?? ""

        return PDFSkriver.lag(bunntekst: "\(firma) · Regnskap \(g.aar)") { s in
            // Topp
            s.logotopp(firma: firma, tittel: "REGNSKAP", undertittel: String(g.aar))
            s.tekst([eier, orgnr.isEmpty ? "" : "Org.nr. \(orgnr)"].filter { !$0.isEmpty }.joined(separator: " · "),
                    font: .systemFont(ofSize: 10), farge: PDFSkriver.graa)
            s.tekst("Laget \(dato(.now)). Tallene er hentet fra appen og er et grunnlag, ikke et revidert regnskap.",
                    font: .systemFont(ofSize: 9), farge: PDFSkriver.graa)

            // Resultat
            s.overskrift("Resultat")
            s.rad("Inntekter", kr(o.inntekter))
            s.rad("Utgifter fra bilag", "−" + kr(o.utgifter))
            if o.avskrivninger > 0 { s.rad("Avskrivninger", "−" + kr(o.avskrivninger)) }
            if o.kjorefradrag > 0 { s.rad("Kjøring med privat bil (\(Fakturering.antall(o.kjoreKm)) km)", "−" + kr(o.kjorefradrag)) }
            if o.hjemmekontor > 0 { s.rad("Hjemmekontor (sjablong)", "−" + kr(o.hjemmekontor)) }
            s.strek()
            s.rad("Overskudd", kr(o.overskudd), uthevet: true)
            s.rad("Beregnet skatt fra foretaket", kr(max(0, o.skatt.ekstraSkatt)))
            if g.mvaRegistrert { s.rad("Inngående mva på bilag", kr(o.inngaendeMva)) }

            // Skattemeldingen
            s.overskrift("Til næringsspesifikasjonen i skattemeldingen")
            let poster = [("Driftsinntekter", n.inntekter), ("Driftskostnader", n.kostnader)]
            for (tittel, liste) in poster where !liste.isEmpty {
                s.tabell([.init(tittel, 0, uthevet: true)])
                for p in liste {
                    s.tabell([.init(p.konto, 50), .init(p.navn, 0), .init(kr(p.belop), 90, hoyre: true)])
                }
            }
            s.strek()
            s.rad("Årsresultat", kr(n.resultat), uthevet: true)

            // Utgifter per kategori
            let perKategori = Dictionary(grouping: bilag, by: \.kategori)
            if !perKategori.isEmpty {
                s.overskrift("Utgifter per kategori")
                s.tabell([.init("Kategori", 0), .init("Antall", 50, hoyre: true), .init("Beløp", 90, hoyre: true),
                          .init("Fradrag", 90, hoyre: true)], topp: true)
                for k in Utgiftskategori.allCases {
                    guard let liste = perKategori[k] else { continue }
                    s.tabell([.init(k.navn, 0), .init("\(liste.count)", 50, hoyre: true),
                              .init(kr(liste.reduce(0) { $0 + $1.belop }), 90, hoyre: true),
                              .init(kr(liste.reduce(0) { $0 + $1.fradrag(mvaRegistrert: g.mvaRegistrert) }), 90, hoyre: true)])
                }
            }

            // Inntekter
            s.overskrift("Inntekter (\(inntekter.count))")
            if inntekter.isEmpty { s.tekst("Ingen inntekter.", font: .systemFont(ofSize: 10), farge: PDFSkriver.graa) }
            else {
                s.tabell([.init("Dato", 62), .init("Kilde", 90), .init("Notat", 0), .init("Beløp", 90, hoyre: true)], topp: true)
                for i in inntekter {
                    s.tabell([.init(dato(i.dato), 62), .init(i.kilde, 90), .init(i.notat, 0), .init(kr(i.belop), 90, hoyre: true)])
                }
            }

            // Fakturaer
            if !fakturaer.isEmpty {
                s.overskrift("Fakturaer (\(fakturaer.count))")
                s.tabell([.init("Nr.", 36), .init("Dato", 62), .init("Kunde", 0), .init("Status", 70),
                          .init("Sum", 90, hoyre: true)], topp: true)
                for f in fakturaer {
                    s.tabell([.init("\(f.nummer)", 36), .init(dato(f.fakturadato), 62),
                              .init((f.erKreditnota ? "Kreditnota: " : "") + f.kundeNavn, 0), .init(f.status.navn, 70),
                              .init(kr(f.total), 90, hoyre: true)])
                }
            }

            // Bilag
            s.overskrift("Bilag (\(bilag.count))")
            if bilag.isEmpty { s.tekst("Ingen bilag.", font: .systemFont(ofSize: 10), farge: PDFSkriver.graa) }
            else {
                s.tabell([.init("Dato", 62), .init("Hva", 0), .init("Kategori", 100), .init("Beløp", 75, hoyre: true),
                          .init("Fradrag", 75, hoyre: true)], topp: true)
                for b in bilag {
                    s.tabell([.init(dato(b.dato), 62), .init(b.tittel.isEmpty ? "–" : b.tittel, 0), .init(b.kategori.navn, 100),
                              .init(kr(b.belop), 75, hoyre: true),
                              .init(kr(b.fradrag(mvaRegistrert: g.mvaRegistrert)), 75, hoyre: true)])
                }
                s.strek()
                s.tabell([.init("Sum", 0, uthevet: true),
                          .init(kr(bilag.reduce(0) { $0 + $1.belop }), 75, hoyre: true, uthevet: true),
                          .init(kr(bilag.reduce(0) { $0 + $1.fradrag(mvaRegistrert: g.mvaRegistrert) }), 75, hoyre: true, uthevet: true)])
            }
        }
    }

    private static func kr(_ v: Double) -> String { Fakturering.kroner(v) }

    private static func dato(_ d: Date) -> String {
        var f = Date.FormatStyle(date: .numeric, time: .omitted).locale(Locale(identifier: "nb_NO"))
        f.timeZone = Frister.kalender.timeZone
        return d.formatted(f)
    }
}

/// Skriver tekst og tabeller nedover A4-sider og lager ny side når det er fullt.
final class PDFSkriver {
    struct Kolonne {
        let tekst: String
        /// Bredde i punkter. 0 betyr «resten av plassen».
        let bredde: CGFloat
        var hoyre = false
        var uthevet = false

        init(_ tekst: String, _ bredde: CGFloat, hoyre: Bool = false, uthevet: Bool = false) {
            self.tekst = tekst
            self.bredde = bredde
            self.hoyre = hoyre
            self.uthevet = uthevet
        }
    }

    static let side = CGRect(x: 0, y: 0, width: 595, height: 842)
    static let svart = UIColor(red: 0.11, green: 0.13, blue: 0.15, alpha: 1)
    static let graa = UIColor(red: 0.42, green: 0.45, blue: 0.48, alpha: 1)
    static let petrol = UIColor(red: 0.09, green: 0.20, blue: 0.23, alpha: 1)
    static let linje = UIColor(red: 0.86, green: 0.87, blue: 0.88, alpha: 1)
    static let fjell = UIColor(red: 0.55, green: 0.78, blue: 0.81, alpha: 1)

    private let marg: CGFloat = 44
    private let bunn: CGFloat = 50
    private let ctx: UIGraphicsPDFRendererContext
    private let bunntekst: String
    private var y: CGFloat = 0
    private var sidenr = 0
    /// Overskriftsraden i tabellen som skrives nå. Gjentas øverst når tabellen fortsetter på neste side.
    private var tabelltopp: [Kolonne]?

    private var bredde: CGFloat { Self.side.width - 2 * marg }

    private init(ctx: UIGraphicsPDFRendererContext, bunntekst: String) {
        self.ctx = ctx
        self.bunntekst = bunntekst
    }

    static func lag(bunntekst: String, innhold: (PDFSkriver) -> Void) -> Data {
        UIGraphicsPDFRenderer(bounds: side).pdfData { ctx in
            let s = PDFSkriver(ctx: ctx, bunntekst: bunntekst)
            s.nySide()
            innhold(s)
        }
    }

    private func nySide() {
        ctx.beginPage()
        sidenr += 1
        y = marg
        let stil = NSMutableParagraphStyle()
        stil.alignment = .right
        let attr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: Self.graa]
        (bunntekst as NSString).draw(at: CGPoint(x: marg, y: Self.side.height - 30), withAttributes: attr)
        var hoyre = attr
        hoyre[.paragraphStyle] = stil
        ("Side \(sidenr)" as NSString).draw(in: CGRect(x: marg, y: Self.side.height - 30, width: bredde, height: 12),
                                             withAttributes: hoyre)
        if let tabelltopp { tabell(tabelltopp, topp: true) }
    }

    private func plass(_ hoyde: CGFloat) {
        if y + hoyde > Self.side.height - bunn { nySide() }
    }

    /// Tekst over hele bredden, brytes over flere linjer ved behov.
    func tekst(_ s: String, font: UIFont, farge: UIColor = PDFSkriver.svart) {
        guard !s.isEmpty else { return }
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: farge]
        let hoyde = ceil((s as NSString).boundingRect(with: CGSize(width: bredde, height: .greatestFiniteMagnitude),
                                                      options: .usesLineFragmentOrigin, attributes: attr, context: nil).height)
        plass(hoyde)
        (s as NSString).draw(with: CGRect(x: marg, y: y, width: bredde, height: hoyde),
                             options: .usesLineFragmentOrigin, attributes: attr, context: nil)
        y += hoyde + 3
    }

    /// Mørk topp med logo og firmanavn, som på fakturaene. Brukes øverst på første side.
    func logotopp(firma: String, tittel: String, undertittel: String) {
        let hoyde: CGFloat = 82
        Self.petrol.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: Self.side.width, height: hoyde))

        let logo = CGRect(x: marg, y: (hoyde - 30) / 2, width: 30, height: 30)
        // Logomerke tegner fra (0, 0), så stien må flyttes dit logoen skal stå.
        let sti = UIBezierPath(cgPath: Logomerke().path(in: CGRect(origin: .zero, size: logo.size))
            .offsetBy(dx: logo.minX, dy: logo.minY).cgPath)
        Self.fjell.setFill()
        sti.fill()

        let serif = UIFont.systemFont(ofSize: 20, weight: .semibold).fontDescriptor.withDesign(.serif)
            .map { UIFont(descriptor: $0, size: 20) } ?? .systemFont(ofSize: 20, weight: .semibold)
        let navnAttr: [NSAttributedString.Key: Any] = [.font: serif, .foregroundColor: UIColor.white]
        let navnHoyde = (firma as NSString).size(withAttributes: navnAttr).height
        (firma as NSString).draw(with: CGRect(x: logo.maxX + 10, y: (hoyde - navnHoyde) / 2,
                                              width: bredde - 190, height: navnHoyde),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                 attributes: navnAttr, context: nil)

        let hoyre = NSMutableParagraphStyle()
        hoyre.alignment = .right
        let tittelAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 18, weight: .bold),
                                                          .foregroundColor: UIColor.white, .kern: 2,
                                                          .paragraphStyle: hoyre]
        let underAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .medium),
                                                         .foregroundColor: Self.fjell, .paragraphStyle: hoyre]
        (tittel as NSString).draw(in: CGRect(x: marg, y: 24, width: bredde, height: 22), withAttributes: tittelAttr)
        (undertittel as NSString).draw(in: CGRect(x: marg, y: 46, width: bredde, height: 14), withAttributes: underAttr)

        y = hoyde + 22
    }

    func overskrift(_ s: String) {
        tabelltopp = nil
        // Plass til overskriften, tabelltoppen og minst én rad, så de ikke skilles av et sideskift.
        plass(90)
        y += 14
        tekst(s, font: .systemFont(ofSize: 13, weight: .semibold), farge: Self.petrol)
        y += 2
    }

    func strek() {
        plass(6)
        Self.linje.setFill()
        UIRectFill(CGRect(x: marg, y: y + 1, width: bredde, height: 0.5))
        y += 5
    }

    func rad(_ venstre: String, _ hoyre: String, uthevet: Bool = false) {
        tabell([.init(venstre, 0, uthevet: uthevet), .init(hoyre, 120, hoyre: true, uthevet: uthevet)])
    }

    /// Én rad i en tabell. `topp` gir en grå overskriftsrad.
    func tabell(_ kolonner: [Kolonne], topp: Bool = false) {
        let radhoyde: CGFloat = topp ? 16 : 15
        plass(radhoyde)
        let fast = kolonner.reduce(0) { $0 + $1.bredde }
        let antallFleks = max(1, kolonner.filter { $0.bredde == 0 }.count)
        let mellomrom: CGFloat = 8
        let fleks = max(40, (bredde - fast - mellomrom * CGFloat(kolonner.count - 1)) / CGFloat(antallFleks))
        var x = marg
        for k in kolonner {
            let b = k.bredde == 0 ? fleks : k.bredde
            let stil = NSMutableParagraphStyle()
            stil.alignment = k.hoyre ? .right : .left
            stil.lineBreakMode = .byTruncatingTail
            let font: UIFont = topp ? .systemFont(ofSize: 8.5, weight: .semibold)
                : k.uthevet ? .systemFont(ofSize: 10, weight: .semibold) : .systemFont(ofSize: 9.5)
            let attr: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: stil,
                                                       .foregroundColor: topp ? Self.graa : Self.svart]
            (k.tekst as NSString).draw(in: CGRect(x: x, y: y + 2, width: b, height: radhoyde - 2), withAttributes: attr)
            x += b + mellomrom
        }
        y += radhoyde
        if topp {
            tabelltopp = kolonner
            strek()
        }
    }
}
