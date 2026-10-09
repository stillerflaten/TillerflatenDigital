import Foundation

/// Nøkler for innstillinger som lagres med @AppStorage.
enum Innstilling {
    static let lonn = "innstilling.lonn"
    static let mvaRegistrert = "innstilling.mvaRegistrert"
    static let mvaAarstermin = "innstilling.mvaAarstermin"
    static let forskuddsskatt = "innstilling.forskuddsskatt"
    static let hjemmekontor = "innstilling.hjemmekontor"
    static let varsler = "innstilling.varsler"
    static let varselDagerFor = "innstilling.varselDagerFor"
}

/// Regnskapet for ett år, satt sammen av alt du har registrert.
struct Aarsoversikt {
    let aar: Int
    let satser: Skattesatser
    let inntekter: Double
    let utgifter: Double
    let avskrivninger: Double
    let kjorefradrag: Double
    let kjoreKm: Double
    let hjemmekontor: Double
    let inngaendeMva: Double
    let skatt: EnkSkatt

    var fradrag: Double { utgifter + avskrivninger + kjorefradrag + hjemmekontor }
    var overskudd: Double { inntekter - fradrag }

    init(aar: Int, bilag: [Bilag], inntekter: [Inntekt], driftsmidler: [Driftsmiddel], turer: [Kjoretur],
         lonn: Double, mvaRegistrert: Bool, hjemmekontor: Bool) {
        let satser = Skattesatser.gjeldende(for: aar)
        self.aar = aar
        self.satser = satser

        self.inntekter = inntekter.filter { $0.dato.aar == aar }.reduce(0) { $0 + $1.belop }

        let aaretsBilag = bilag.filter { $0.dato.aar == aar }
        self.utgifter = aaretsBilag.reduce(0) { $0 + $1.fradrag(mvaRegistrert: mvaRegistrert) }
        self.inngaendeMva = mvaRegistrert ? aaretsBilag.reduce(0) { $0 + $1.mva * $1.naeringsandel / 100 } : 0

        self.avskrivninger = Aarsoversikt.avskrivning(i: aar, driftsmidler: driftsmidler, satser: satser)

        let km = turer.filter { $0.dato.aar == aar }.reduce(0) { $0 + $1.km }
        self.kjoreKm = km
        self.kjorefradrag = km * satser.kmSatsPrivatBil
        self.hjemmekontor = hjemmekontor ? satser.hjemmekontorSjablong : 0

        let overskudd = self.inntekter - (utgifter + avskrivninger + kjorefradrag + self.hjemmekontor)
        self.skatt = EnkSkatt(lonn: lonn, overskudd: overskudd, satser: satser)
    }

    /// Årets fradrag for utstyr: direkte fradrag for billig utstyr kjøpt i år,
    /// pluss saldoavskrivning for hver gruppe.
    static func avskrivning(i aar: Int, driftsmidler: [Driftsmiddel], satser: Skattesatser) -> Double {
        var sum = 0.0
        var paSaldo: [Saldogruppe: [(aar: Int, belop: Double)]] = [:]
        for d in driftsmidler {
            switch d.metode(satser: satser) {
            case .direkteFradrag(let belop):
                if d.kjopsaar == aar { sum += belop }
            case .saldo(let gruppe, let grunnlag):
                paSaldo[gruppe, default: []].append((aar: d.kjopsaar, belop: grunnlag))
            }
        }
        for (gruppe, kjop) in paSaldo {
            let plan = Avskrivning.saldoplan(anskaffelser: kjop, gruppe: gruppe, tilOgMed: aar, satser: satser)
            sum += plan.first(where: { $0.aar == aar })?.avskrivning ?? 0
        }
        return sum
    }
}

extension Double {
    /// 12 345 kr
    var kr: String {
        formatted(.currency(code: "NOK").precision(.fractionLength(0)).locale(Locale(identifier: "nb_NO")))
    }

    /// 36,8 %
    var prosent: String {
        formatted(.percent.precision(.fractionLength(0...1)).locale(Locale(identifier: "nb_NO")))
    }
}
