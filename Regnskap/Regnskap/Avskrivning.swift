import Foundation

/// Saldogruppene som er aktuelle for et lite app- og nettsideforetak.
/// (Gruppene b, c og e–j gjelder forretningsverdi, varebiler, skip, bygg o.l.)
enum Saldogruppe: String, CaseIterable, Identifiable, Codable {
    case a, d

    var id: String { rawValue }

    var sats: Double {
        switch self {
        case .a: 0.30
        case .d: 0.20
        }
    }

    var navn: String {
        switch self {
        case .a: "Gruppe a – kontormaskiner (30 %)"
        case .d: "Gruppe d – inventar, maskiner, personbil (20 %)"
        }
    }

    var eksempler: String {
        switch self {
        case .a: "Mac, PC, iPad, iPhone, skjerm, skriver"
        case .d: "Kontormøbler, kamera, verktøy, personbil"
        }
    }
}

/// Hva som skjer med ett kjøp av utstyr.
enum Fradragsmetode: Equatable {
    /// Trekkes fra i sin helhet samme år som du kjøper det.
    case direkteFradrag(belop: Double)
    /// Legges i en saldogruppe og avskrives litt hvert år.
    case saldo(gruppe: Saldogruppe, grunnlag: Double)
}

enum Avskrivning {
    /// Avgjør om utstyret kan trekkes fra med en gang eller må avskrives.
    /// - Parameters:
    ///   - kostpris: Pris inkl. mva hvis du ikke er mva-registrert, ellers uten mva.
    ///   - naeringsandel: Hvor stor del (0–1) som brukes i foretaket.
    ///   - levetidMinst3Aar: Om utstyret forventes å vare minst tre år.
    static func metode(kostpris: Double, naeringsandel: Double = 1, levetidMinst3Aar: Bool = true,
                       gruppe: Saldogruppe, satser: Skattesatser) -> Fradragsmetode {
        let belop = kostpris * naeringsandel
        // Grensen gjelder hele kostprisen for gjenstanden, ikke bare næringsdelen.
        if kostpris < satser.direkteFradragGrense || !levetidMinst3Aar {
            return .direkteFradrag(belop: belop)
        }
        return .saldo(gruppe: gruppe, grunnlag: belop)
    }

    struct Aar: Identifiable, Equatable {
        let aar: Int
        let inngaende: Double
        let tilgang: Double
        let avskrivning: Double
        /// Saldoen var under grensen, så resten ble trukket fra på én gang.
        let lavSaldoFradrag: Bool

        var id: Int { aar }
        var grunnlag: Double { inngaende + tilgang }
        var utgaende: Double { grunnlag - avskrivning }
    }

    /// Saldoplan for én gruppe. Alle kjøp i samme gruppe slås sammen til én saldo,
    /// og hele årets avskrivning beregnes av saldoen ved årsslutt (uansett kjøpsmåned).
    /// - Parameter anskaffelser: (år, beløp) for hvert kjøp som skal på saldo.
    static func saldoplan(anskaffelser: [(aar: Int, belop: Double)], gruppe: Saldogruppe,
                          tilOgMed sisteAar: Int, satser: Skattesatser) -> [Aar] {
        guard let forsteAar = anskaffelser.map(\.aar).min(), forsteAar <= sisteAar else { return [] }
        var plan: [Aar] = []
        var saldo = 0.0
        for aar in forsteAar...sisteAar {
            let tilgang = anskaffelser.filter { $0.aar == aar }.reduce(0) { $0 + $1.belop }
            let grunnlag = saldo + tilgang
            guard grunnlag > 0.5 else {
                saldo = 0
                continue
            }
            let lavSaldo = grunnlag < satser.lavSaldoGrense
            let avskrivning = lavSaldo ? grunnlag : (grunnlag * gruppe.sats).rounded()
            plan.append(Aar(aar: aar, inngaende: saldo, tilgang: tilgang, avskrivning: avskrivning, lavSaldoFradrag: lavSaldo))
            saldo = grunnlag - avskrivning
        }
        return plan
    }

    /// Avskrivning for ett enkelt kjøp, år for år, til saldoen er borte.
    static func plan(forEttKjop kostpris: Double, aar: Int, gruppe: Saldogruppe, satser: Skattesatser) -> [Aar] {
        saldoplan(anskaffelser: [(aar: aar, belop: kostpris)], gruppe: gruppe, tilOgMed: aar + 30, satser: satser)
    }
}
