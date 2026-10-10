import SwiftUI

/// Fakturaen slik den ser ut på papir (A4). Brukes både til forhåndsvisning og PDF.
struct FakturaSide: View {
    let faktura: Faktura

    static let a4 = CGSize(width: 595, height: 842)

    private let svart = Color(red: 0.11, green: 0.13, blue: 0.15)
    private let graa = Color(red: 0.42, green: 0.45, blue: 0.48)
    private let linje = Color(red: 0.86, green: 0.87, blue: 0.88)
    private let petrol = Color(red: 0.09, green: 0.20, blue: 0.23)
    private let fjell = Color(red: 0.55, green: 0.78, blue: 0.81)

    private func dato(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(Locale(identifier: "nb_NO")))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topp
            VStack(alignment: .leading, spacing: 22) {
                parter
                linjer
                summer
                betaling
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
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var topp: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                Logomerke()
                    .fill(fjell)
                    .frame(width: 30, height: 30)
                Text(faktura.selgerNavn.isEmpty ? Firma.lagretNavn : faktura.selgerNavn)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("FAKTURA")
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
                Text(faktura.selgerEier).fontWeight(.semibold)
                Text(faktura.selgerAdresse)
                Text("Org.nr. \(Fakturering.orgnr(faktura.selgerOrgnr))\(faktura.mvaSats > 0 ? " MVA" : "")")
                Text(faktura.selgerEpost)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                rad("Fakturadato", dato(faktura.fakturadato))
                rad("Levert", dato(faktura.leveringsdato))
                rad("Forfall", dato(faktura.forfallsdato), uthevet: true)
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
                    Text(Fakturering.kroner(l.enhetspris)).frame(width: 80, alignment: .trailing)
                    Text(Fakturering.kroner(l.belop)).frame(width: 90, alignment: .trailing)
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
                    Text("Å betale")
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

    private var betaling: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 2) {
                overskrift("Kontonummer")
                Text(Fakturering.kontonr(faktura.selgerKontonr))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                overskrift("Beløp")
                Text(Fakturering.kroner(faktura.total))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                overskrift("Forfall")
                Text(dato(faktura.forfallsdato))
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottomLeading) {
            Text("Merk betalingen med fakturanummer \(faktura.nummer).")
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
            Text([faktura.selgerNavn, "Org.nr. \(Fakturering.orgnr(faktura.selgerOrgnr))", faktura.selgerEpost]
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
    static func data(for faktura: Faktura) -> Data {
        let renderer = ImageRenderer(content: FakturaSide(faktura: faktura))
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
        Arkiv.filnavn(dato: faktura.fakturadato, tittel: "Faktura \(faktura.nummer) \(faktura.kundeNavn)") + ".pdf"
    }

    /// Lagrer PDF-en i en midlertidig fil, så den kan deles eller sendes på e-post.
    @MainActor
    static func fil(for faktura: Faktura) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filnavn(for: faktura))
        try? data(for: faktura).write(to: url, options: .atomic)
        return url
    }
}
