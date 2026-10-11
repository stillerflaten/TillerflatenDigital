import Foundation

enum Mva {
    static let hoySats = 0.25

    /// Datoen foretaket ble mva-registrert, eller nil hvis den ikke er oppgitt (da gjelder registreringen hele tiden).
    static var registrertFra: Date? {
        let sekunder = UserDefaults.standard.double(forKey: Innstilling.mvaFra)
        return sekunder > 0 ? Date(timeIntervalSince1970: sekunder) : nil
    }

    /// En periode i mva-meldingen.
    struct Termin: Hashable, Identifiable {
        let aar: Int
        /// 1–6 for vanlige terminer, 0 for årstermin.
        let nr: Int

        var id: String { "\(aar)-\(nr)" }

        var fra: Date {
            Frister.kalender.date(from: DateComponents(year: aar, month: nr == 0 ? 1 : nr * 2 - 1, day: 1))!
        }

        /// Første dag etter perioden.
        var til: Date {
            Frister.kalender.date(byAdding: .month, value: nr == 0 ? 12 : 2, to: fra)!
        }

        var navn: String {
            let maaneder = ["", "januar–februar", "mars–april", "mai–juni", "juli–august", "september–oktober", "november–desember"]
            return nr == 0 ? "Hele \(aar) (årstermin)" : "Termin \(nr): \(maaneder[nr]) \(aar)"
        }

        func inneholder(_ dato: Date) -> Bool { dato >= fra && dato < til }

        static func alle(aar: Int, aarstermin: Bool) -> [Termin] {
            aarstermin ? [Termin(aar: aar, nr: 0)] : (1...6).map { Termin(aar: aar, nr: $0) }
        }

        static func gjeldende(_ dato: Date = .now, aarstermin: Bool) -> Termin {
            let aar = dato.aar
            let maaned = Frister.kalender.component(.month, from: dato)
            return Termin(aar: aar, nr: aarstermin ? 0 : (maaned + 1) / 2)
        }
    }
}

/// Tallene du trenger til mva-meldingen for én termin.
///
/// Kodene er de samme som i mva-meldingen i Altinn. Appen kjenner bare til det som
/// er registrert her: fakturaer, App Store-inntekter og bilag.
struct MvaMelding {
    let termin: Mva.Termin

    /// Kode 3: salg i Norge med 25 % mva (fakturaene dine).
    var salgGrunnlag: Double = 0
    var salgMva: Double = 0
    /// Kode 52: tjenester levert til utlandet, fritatt (App Store-inntekter fra Apple).
    var fritattUtland: Double = 0
    /// Kode 1: mva på kjøp i Norge som du får tilbake.
    var inngaendeMva: Double = 0
    /// Kode 86: tjenester kjøpt fra utlandet (omvendt avgiftsplikt).
    var utlandGrunnlag: Double = 0
    var utlandBeregnet: Double = 0
    var utlandFradrag: Double = 0
    /// Inntekter lagt inn for hånd som appen ikke vet mva-behandlingen av.
    var ukjenteInntekter: Double = 0

    /// Positivt beløp: du skal betale. Negativt: du får penger tilbake.
    var aaBetale: Double {
        Fakturering.rund(salgMva + utlandBeregnet - inngaendeMva - utlandFradrag)
    }

    init(termin: Mva.Termin, bilag: [Bilag], inntekter: [Inntekt], fakturaer: [Faktura],
         mvaFra: Date? = Mva.registrertFra) {
        self.termin = termin
        let start = mvaFra.map { max(termin.fra, Frister.kalender.startOfDay(for: $0)) } ?? termin.fra
        func iPerioden(_ d: Date) -> Bool { d >= start && d < termin.til }

        for f in fakturaer where f.nummer > 0 && f.mvaSats > 0 && iPerioden(f.fakturadato) {
            salgGrunnlag += f.sumEksMva
            salgMva += f.mvaBelop
        }
        for i in inntekter where iPerioden(i.dato) {
            switch i.kilde {
            case "App Store": fritattUtland += i.belop
            case "Faktura": break  // Telles fra fakturaene på fakturadatoen.
            default: ukjenteInntekter += i.belop
            }
        }
        for b in bilag where iPerioden(b.dato) {
            if b.fraUtlandet {
                let mva = b.belop * Mva.hoySats
                utlandGrunnlag += b.belop
                utlandBeregnet += mva
                utlandFradrag += mva * b.naeringsandel / 100
            } else {
                inngaendeMva += b.mva * b.naeringsandel / 100
            }
        }
        salgGrunnlag = Fakturering.rund(salgGrunnlag)
        salgMva = Fakturering.rund(salgMva)
        inngaendeMva = Fakturering.rund(inngaendeMva)
        utlandBeregnet = Fakturering.rund(utlandBeregnet)
        utlandFradrag = Fakturering.rund(utlandFradrag)
    }
}
