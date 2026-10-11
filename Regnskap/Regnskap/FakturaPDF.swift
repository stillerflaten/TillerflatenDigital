import SwiftUI

/// Fakturaen slik den ser ut på papir (A4). Brukes både til forhåndsvisning og PDF.
struct FakturaSide: View {
    let faktura: Faktura
    /// Satt når siden er en purring på fakturaen.
    var purring: Purring? = nil

    struct Purring {
        /// 1 for første purring, 2 for andre osv.
        let nr: Int
        let frist: Date
        /// Det kunden fortsatt skal betale.
        let belop: Double
    }

    static let a4 = CGSize(width: 595, height: 842)

    private let svart = Color(red: 0.11, green: 0.13, blue: 0.15)
    private let graa = Color(red: 0.42, green: 0.45, blue: 0.48)
    private let linje = Color(red: 0.86, green: 0.87, blue: 0.88)
    private let petrol = Color(red: 0.09, green: 0.20, blue: 0.23)
    private let fjell = Color(red: 0.55, green: 0.78, blue: 0.81)

    // Ferdige fakturaer bruker opplysningene som ble låst. Et utkast viser det som står i Firmaopplysninger nå.
    private var erUtkast: Bool { faktura.nummer == 0 }
    private func firma(_ lagret: String, _ nokkel: String, standard: String = "") -> String {
        erUtkast ? (UserDefaults.standard.string(forKey: nokkel) ?? standard) : lagret
    }
    private var selgerNavn: String { firma(faktura.selgerNavn, Firma.navn, standard: Firma.standardNavn) }
    private var selgerEier: String { firma(faktura.selgerEier, Firma.eier) }
    private var selgerAdresse: String { firma(faktura.selgerAdresse, Firma.adresse) }
    private var selgerOrgnr: String { firma(faktura.selgerOrgnr, Firma.orgnr) }
    private var selgerKontonr: String { firma(faktura.selgerKontonr, Firma.kontonr) }
    private var selgerEpost: String { firma(faktura.selgerEpost, Firma.epost, standard: Firma.standardEpost) }

    private func dato(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(Locale(identifier: "nb_NO")))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topp
            VStack(alignment: .leading, spacing: 22) {
                parter
                if let purring {
                    purretekst(purring)
                }
                linjer
                summer
                if faktura.erKreditnota {
                    kreditering
                } else {
                    betaling
                }
                if !faktura.merknad.trimmet.isEmpty {
                    Text(faktura.merknad)
                        .font(.system(size: 10))
                        .foregroundStyle(svart)
                }
                Spacer(minLength: 0)
                bunn
            }
            .padding(.horizontal, 44)
            .padding(.top, 26)
            .padding(.bottom, 30)
        }
        .frame(width: Self.a4.width, height: Self.a4.height, alignment: .topLeading)
        .overlay {
            if erUtkast {
                Text("UTKAST")
                    .font(.system(size: 110, weight: .black))
                    .foregroundStyle(Color.red.opacity(0.12))
                    .rotationEffect(.degrees(-30))
            }
        }
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var topp: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                Logomerke()
                    .fill(fjell)
                    .frame(width: 30, height: 30)
                Text(selgerNavn)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(purring.map { $0.nr > 1 ? "PURRING \($0.nr)" : "PURRING" } ?? (faktura.erKreditnota ? "KREDITNOTA" : "FAKTURA"))
                    .font(.system(size: 18, weight: .bold))
                    .tracking(2)
                Text(faktura.nummer > 0 ? "Nr. \(faktura.nummer)" : "UTKAST")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(fjell)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 44)
        .padding(.vertical, 26)
        .background(petrol)
    }

    private var parter: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                overskrift("Faktura til")
                Text(faktura.kundeNavn).fontWeight(.semibold)
                Text(faktura.kundeAdresse)
                if !faktura.kundeOrgnr.trimmet.isEmpty {
                    Text("Org.nr. \(Fakturering.orgnr(faktura.kundeOrgnr))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                overskrift("Fra")
                Text(selgerEier).fontWeight(.semibold)
                Text(selgerAdresse)
                Text("Org.nr. \(Fakturering.orgnr(selgerOrgnr))\(faktura.mvaSats > 0 ? " MVA" : "")")
                Text(selgerEpost)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                rad("Fakturadato", dato(faktura.fakturadato))
                rad("Levert", dato(faktura.leveringsdato))
                if faktura.erKreditnota {
                    rad("Krediterer", "Faktura \(faktura.kreditererNummer)", uthevet: true)
                } else if let purring {
                    rad("Opprinnelig forfall", dato(faktura.forfallsdato))
                    rad("Ny frist", dato(purring.frist), uthevet: true)
                } else {
                    rad("Forfall", dato(faktura.forfallsdato), uthevet: true)
                }
            }
            .fixedSize()
        }
        .font(.system(size: 10))
        .foregroundStyle(svart)
    }

    private var linjer: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Beskrivelse").frame(maxWidth: .infinity, alignment: .leading)
                Text("Antall").frame(width: 50, alignment: .trailing)
                Text("Pris").frame(width: 80, alignment: .trailing)
                Text("Beløp").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(graa)
            .padding(.bottom, 6)
            Rectangle().fill(svart).frame(height: 1)
            ForEach(faktura.sorterteLinjer) { l in
                HStack(alignment: .top) {
                    Text(l.beskrivelse).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Fakturering.antall(l.antall)).frame(width: 50, alignment: .trailing)
                    Text(Fakturering.kroner(faktura.fortegn * l.enhetspris)).frame(width: 80, alignment: .trailing)
                    Text(Fakturering.kroner(faktura.fortegn * l.belop)).frame(width: 90, alignment: .trailing)
                }
                .font(.system(size: 10))
                .monospacedDigit()
                .padding(.vertical, 7)
                Rectangle().fill(linje).frame(height: 0.5)
            }
        }
        .foregroundStyle(svart)
    }

    private var summer: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                rad("Sum eks. mva", Fakturering.kroner(faktura.sumEksMva))
                rad(faktura.mvaSats > 0 ? "Mva \(Int((faktura.mvaSats * 100).rounded())) %" : "Mva",
                    Fakturering.kroner(faktura.mvaBelop))
                Rectangle().fill(svart).frame(width: 200, height: 1)
                HStack {
                    Text(faktura.erKreditnota ? "Til gode" : "Å betale")
                    Spacer()
                    Text(Fakturering.kroner(faktura.total))
                }
                .font(.system(size: 13, weight: .bold))
                .frame(width: 200)
                if faktura.mvaSats == 0 {
                    Text("Foretaket er ikke registrert i Merverdiavgiftsregisteret.\nMva er derfor ikke beregnet.")
                        .font(.system(size: 8))
                        .foregroundStyle(graa)
                        .multilineTextAlignment(.trailing)
                        .padding(.top, 4)
                }
            }
            .font(.system(size: 10))
            .monospacedDigit()
        }
        .foregroundStyle(svart)
    }

    private func purretekst(_ p: Purring) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            overskrift("Påminnelse")
            Text("Vi kan ikke se å ha mottatt betaling for faktura nr. \(faktura.nummer), som forfalt \(dato(faktura.forfallsdato)). Vennligst betal \(Fakturering.kroner(p.belop)) innen \(dato(p.frist)). Har du betalt de siste dagene, kan du se bort fra denne purringen.")
                .font(.system(size: 11))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(fjell, lineWidth: 1))
        .foregroundStyle(svart)
    }

    private var kreditering: some View {
        VStack(alignment: .leading, spacing: 4) {
            overskrift("Kreditnota")
            Text("Beløpet krediteres faktura nr. \(faktura.kreditererNummer). Har du allerede betalt fakturaen, får du beløpet tilbake.")
                .font(.system(size: 11))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.95, green: 0.96, blue: 0.95), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(svart)
    }

    private var betaling: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 2) {
                overskrift("Kontonummer")
                Text(Fakturering.kontonr(selgerKontonr))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                overskrift("Beløp")
                Text(Fakturering.kroner(purring?.belop ?? faktura.total))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                overskrift(purring == nil ? "Forfall" : "Ny frist")
                Text(dato(purring?.frist ?? faktura.forfallsdato))
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottomLeading) {
            Text(erUtkast ? "Utkast. Fakturanummeret kommer når fakturaen ferdigstilles."
                          : "Merk betalingen med fakturanummer \(faktura.nummer).")
                .font(.system(size: 9))
                .foregroundStyle(graa)
                .offset(y: 16)
        }
        .padding(16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.95, green: 0.96, blue: 0.95), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(svart)
    }

    private var bunn: some View {
        VStack(spacing: 6) {
            Rectangle().fill(linje).frame(height: 0.5)
            Text([selgerNavn, "Org.nr. \(Fakturering.orgnr(selgerOrgnr))", selgerEpost]
                .filter { !$0.isEmpty }
                .joined(separator: "  ·  "))
                .font(.system(size: 8))
                .foregroundStyle(graa)
        }
    }

    private func overskrift(_ tekst: String) -> some View {
        Text(tekst.uppercased())
            .font(.system(size: 8, weight: .semibold))
            .tracking(1)
            .foregroundStyle(graa)
            .padding(.bottom, 2)
    }

    private func rad(_ tittel: String, _ verdi: String, uthevet: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(tittel).foregroundStyle(graa)
            Spacer(minLength: 0)
            Text(verdi).fontWeight(uthevet ? .semibold : .regular)
        }
        .frame(width: 200)
    }
}

enum FakturaPDF {
    /// Lager PDF-en for fakturaen.
    @MainActor
    static func data(for faktura: Faktura, purring: FakturaSide.Purring? = nil) -> Data {
        let renderer = ImageRenderer(content: FakturaSide(faktura: faktura, purring: purring))
        let data = NSMutableData()
        renderer.render { _, tegn in
            var boks = CGRect(origin: .zero, size: FakturaSide.a4)
            guard let forbruker = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: forbruker, mediaBox: &boks, nil) else { return }
            ctx.beginPDFPage(nil)
            tegn(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return data as Data
    }

    static func filnavn(for faktura: Faktura) -> String {
        let type = faktura.erKreditnota ? "Kreditnota" : "Faktura"
        let hva = faktura.nummer > 0 ? "\(type) \(faktura.nummer)" : "Utkast \(type.lowercased())"
        return Arkiv.filnavn(dato: faktura.fakturadato, tittel: "\(hva) \(faktura.kundeNavn)") + ".pdf"
    }

    /// Lagrer PDF-en i en midlertidig fil, så den kan deles eller sendes på e-post.
    @MainActor
    static func fil(for faktura: Faktura) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filnavn(for: faktura))
        try? data(for: faktura).write(to: url, options: .atomic)
        return url
    }

    /// PDF med purring på fakturaen.
    @MainActor
    static func purrefil(for faktura: Faktura, purring: FakturaSide.Purring) -> URL {
        let navn = Arkiv.filnavn(dato: .now, tittel: "Purring \(purring.nr) faktura \(faktura.nummer) \(faktura.kundeNavn)") + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(navn)
        try? data(for: faktura, purring: purring).write(to: url, options: .atomic)
        return url
    }
}
