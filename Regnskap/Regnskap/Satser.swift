import Foundation

/// Alle satser og grenser appen regner med, samlet på ett sted.
/// Når nye satser kommer (statsbudsjettet legges frem i oktober og vedtas i desember),
/// legger du inn et nytt år her, f.eks. `aar2027`, og oppdaterer `for(aar:)`.
struct Skattesatser {
    let aar: Int

    // Skatt på alminnelig inntekt (overskudd etter fradrag)
    let alminneligSats: Double
    let personfradrag: Double

    // Minstefradrag i lønn
    let minstefradragSats: Double
    let minstefradragMaks: Double

    // Trinnskatt: (innslagspunkt, sats)
    let trinnskatt: [(grense: Double, sats: Double)]

    // Trygdeavgift
    let trygdeavgiftLonn: Double
    let trygdeavgiftNaering: Double
    let trygdeavgiftNedreGrense: Double
    let trygdeavgiftOpptrapping: Double

    // Driftsmidler
    let direkteFradragGrense: Double   // under dette kan utstyr trekkes fra med en gang
    let lavSaldoGrense: Double         // saldo under dette kan trekkes fra i sin helhet

    // Merverdiavgift
    let mvaRegistreringsgrense: Double

    // Sjabloner for næringsdrivende
    let hjemmekontorSjablong: Double
    let kmSatsPrivatBil: Double

    static let aar2026 = Skattesatser(
        aar: 2026,
        alminneligSats: 0.22,
        personfradrag: 114_540,
        minstefradragSats: 0.46,
        minstefradragMaks: 95_700,
        trinnskatt: [
            (226_100, 0.017),
            (318_300, 0.040),
            (725_050, 0.137),
            (980_100, 0.168),
            (1_467_200, 0.178),
        ],
        trygdeavgiftLonn: 0.076,
        trygdeavgiftNaering: 0.108,
        trygdeavgiftNedreGrense: 99_650,
        trygdeavgiftOpptrapping: 0.25,
        direkteFradragGrense: 30_000,
        lavSaldoGrense: 30_000,
        mvaRegistreringsgrense: 50_000,
        hjemmekontorSjablong: 1_850,
        kmSatsPrivatBil: 3.50
    )

    /// Satsene som brukes for et gitt år. Foreløpig finnes bare 2026,
    /// så andre år bruker 2026-satsene (se `erEksakt`).
    static func gjeldende(for aar: Int) -> Skattesatser {
        aar2026
    }

    static func erEksakt(for aar: Int) -> Bool {
        aar == aar2026.aar
    }
}

/// Lenker til kildene, så du kan sjekke tallene selv.
enum Kilder {
    static let skattesatser = URL(string: "https://www.regjeringen.no/no/tema/okonomi-og-budsjett/skatter-og-avgifter/skattesatser-2026/id3121978/")!
    static let forskuddsskatt = URL(string: "https://www.skatteetaten.no/person/skatt/skattekort/forskuddsskatt/")!
    static let mva = URL(string: "https://www.skatteetaten.no/bedrift-og-organisasjon/avgifter/mva/registrering/")!
    static let driftsmidler = URL(string: "https://www.skatteetaten.no/bedrift-og-organisasjon/skatt/skattemelding-naringsdrivende/fradrag/eiendeler-utstyr-eiendom/")!
    static let skattekalkulator = URL(string: "https://www.skatteetaten.no/person/skatt/hjelp-til-riktig-skatt/skattekalkulator/")!
}
