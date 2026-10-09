import Foundation

/// Lager en CSV-fil (åpnes i Numbers eller Excel) med årets bilag og inntekter.
enum Eksport {
    static func csv(aar: Int, bilag: [Bilag], inntekter: [Inntekt], mvaRegistrert: Bool) -> String {
        let datoFormat = Date.FormatStyle(date: .numeric, time: .omitted).locale(Locale(identifier: "nb_NO"))
        func tall(_ d: Double) -> String {
            d.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "nb_NO")))
        }
        func felt(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }

        var linjer = ["Type;Dato;Beskrivelse;Kategori;Beløp;Mva;Næringsandel %;Fradrag;Notat"]
        for i in inntekter.filter({ $0.dato.aar == aar }).sorted(by: { $0.dato < $1.dato }) {
            linjer.append(["Inntekt", i.dato.formatted(datoFormat), felt(i.kilde), "", tall(i.belop), "", "", "", felt(i.notat)]
                .joined(separator: ";"))
        }
        for b in bilag.filter({ $0.dato.aar == aar }).sorted(by: { $0.dato < $1.dato }) {
            linjer.append([b.erRegning ? "Regning" : "Kvittering", b.dato.formatted(datoFormat), felt(b.tittel),
                           felt(b.kategori.navn), tall(b.belop), tall(b.mva), tall(b.naeringsandel),
                           tall(b.fradrag(mvaRegistrert: mvaRegistrert)), felt(b.notat)]
                .joined(separator: ";"))
        }
        return linjer.joined(separator: "\n")
    }

    static func csvFil(aar: Int, bilag: [Bilag], inntekter: [Inntekt], mvaRegistrert: Bool) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Regnskap \(aar).csv")
        let innhold = csv(aar: aar, bilag: bilag, inntekter: inntekter, mvaRegistrert: mvaRegistrert)
        // BOM gjør at Excel skjønner at filen er UTF-8 (æ, ø, å)
        try? ("\u{FEFF}" + innhold).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
