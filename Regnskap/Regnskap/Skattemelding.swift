import SwiftUI
import SwiftData

/// Årets tall gruppert slik de føres i næringsspesifikasjonen i skattemeldingen.
///
/// Kontonumrene er forslag etter standard kontoplan (NS 4102), som næringsspesifikasjonen bygger på.
struct Naeringsspesifikasjon {
    struct Post: Identifiable {
        let konto: String
        let navn: String
        let belop: Double
        var forklaring: String? = nil
        var id: String { konto + navn }
    }

    let aar: Int
    let inntekter: [Post]
    let kostnader: [Post]
    /// Bilag i kategorien «avskrives» uten at noe er lagt inn under Avskrivning.
    let manglerAvskrivning: Bool

    var sumInntekter: Double { inntekter.reduce(0) { $0 + $1.belop } }
    var sumKostnader: Double { kostnader.reduce(0) { $0 + $1.belop } }
    var resultat: Double { sumInntekter - sumKostnader }

    static func konto(for kategori: Utgiftskategori) -> (konto: String, navn: String) {
        switch kategori {
        case .programvare: ("6552", "Programvare og abonnementer")
        case .utstyr: ("6540", "Inventar og utstyr (ikke aktivert)")
        case .driftsmiddel: ("6000", "Avskrivning på varige driftsmidler")
        case .kontor: ("6800", "Kontorrekvisita")
        case .telefonInternett: ("6900", "Telefon og internett")
        case .kurs: ("6860", "Møte, kurs og oppdatering")
        case .markedsforing: ("7320", "Reklamekostnad")
        case .reise: ("7140", "Reisekostnad, ikke oppgavepliktig")
        case .regnskap: ("7770", "Bank, gebyrer og regnskap")
        case .annet: ("7790", "Annen kostnad, fradragsberettiget")
        }
    }

    init(aar: Int, bilag: [Bilag], inntekter alleInntekter: [Inntekt], driftsmidler: [Driftsmiddel],
         turer: [Kjoretur], mvaRegistrert: Bool, hjemmekontor: Bool, mvaFra: Date? = Mva.registrertFra) {
        let o = Aarsoversikt(aar: aar, bilag: bilag, inntekter: alleInntekter, driftsmidler: driftsmidler,
                             turer: turer, lonn: 0, mvaRegistrert: mvaRegistrert, hjemmekontor: hjemmekontor)
        self.aar = aar

        // Inntekter
        var appStore = 0.0, medMva = 0.0, utenMva = 0.0
        for i in alleInntekter where i.dato.aar == aar {
            let registrert = mvaRegistrert && (mvaFra.map { i.dato >= Frister.kalender.startOfDay(for: $0) } ?? true)
            if i.kilde == "App Store" {
                appStore += i.belop
            } else if registrert {
                medMva += i.belop
            } else {
                utenMva += i.belop
            }
        }
        var inn: [Post] = []
        if medMva != 0 {
            inn.append(Post(konto: "3000", navn: "Salgsinntekt, avgiftspliktig", belop: medMva,
                            forklaring: "Fakturaer og annet salg i Norge etter at du ble mva-registrert. Beløpet er uten mva."))
        }
        if appStore != 0 {
            inn.append(Post(konto: "3100", navn: "Salgsinntekt, avgiftsfri", belop: appStore,
                            forklaring: "Utbetalinger fra Apple. Apple holder til i utlandet, så salget er fritatt for norsk mva."))
        }
        if utenMva != 0 {
            inn.append(Post(konto: mvaRegistrert ? "3100" : "3000", navn: "Salgsinntekt", belop: utenMva,
                            forklaring: "Fakturaer og annet salg mens du ikke var mva-registrert."))
        }
        inntekter = inn

        // Kostnader fra bilag, gruppert etter konto
        var perKategori: [Utgiftskategori: Double] = [:]
        for b in bilag where b.dato.aar == aar && b.kategori != .driftsmiddel {
            perKategori[b.kategori, default: 0] += b.fradrag(mvaRegistrert: mvaRegistrert, mvaFra: mvaFra)
        }
        var kost: [Post] = []
        if o.avskrivninger > 0 {
            kost.append(Post(konto: "6000", navn: "Avskrivning på varige driftsmidler", belop: o.avskrivninger,
                             forklaring: "Fra Kalkulatorer → Avskrivning. Saldoskjemaet fylles ut i næringsspesifikasjonen."))
        }
        for kategori in Utgiftskategori.allCases where kategori != .driftsmiddel {
            guard let belop = perKategori[kategori], belop != 0 else { continue }
            let k = Self.konto(for: kategori)
            kost.append(Post(konto: k.konto, navn: k.navn, belop: belop))
        }
        if o.kjorefradrag > 0 {
            kost.append(Post(konto: "–", navn: "Kjøring med privat bil", belop: o.kjorefradrag,
                             forklaring: "\(Int(o.kjoreKm)) km fra kjøreloggen × \(o.satser.kmSatsPrivatBil.formatted()) kr. Føres som fradrag for bruk av privat bil i næringen. Ta vare på kjøreloggen."))
        }
        if o.hjemmekontor > 0 {
            kost.append(Post(konto: "–", navn: "Kontor i hjemmet (sjablong)", belop: o.hjemmekontor,
                             forklaring: "Standardfradrag for et rom som bare brukes til foretaket. Føres som sjablongfradrag for hjemmekontor."))
        }
        kostnader = kost.sorted { ($0.konto == "–" ? "9999" : $0.konto) < ($1.konto == "–" ? "9999" : $1.konto) }

        manglerAvskrivning = bilag.contains { $0.dato.aar == aar && $0.kategori == .driftsmiddel }
            && !driftsmidler.contains { $0.kjopsaar == aar }
    }
}

struct SkattemeldingView: View {
    let aar: Int

    @Query private var bilag: [Bilag]
    @Query private var inntekter: [Inntekt]
    @Query private var driftsmidler: [Driftsmiddel]
    @Query private var turer: [Kjoretur]

    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false
    @AppStorage(Innstilling.hjemmekontor) private var hjemmekontor = false

    var body: some View {
        let n = Naeringsspesifikasjon(aar: aar, bilag: bilag, inntekter: inntekter, driftsmidler: driftsmidler,
                                      turer: turer, mvaRegistrert: mvaRegistrert, hjemmekontor: hjemmekontor)
        List {
            Section {
                Text("Skattemeldingen for \(String(aar)) leveres innen 31. mai \(String(aar + 1)). Logg inn på skatteetaten.no, velg «Skattemelding» og legg til næringsspesifikasjonen for foretaket. Der fører du tallene under på samme konto.")
                    .font(.callout)
            }

            if n.manglerAvskrivning {
                Section {
                    Label("Du har bilag som skal avskrives, men ikke noe utstyr under Kalkulatorer → Avskrivning for \(String(aar)). Legg det inn der, ellers mangler fradraget.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if n.inntekter.isEmpty {
                    Text("Ingen inntekter i \(String(aar)).").foregroundStyle(.secondary)
                }
                ForEach(n.inntekter) { PostRad(post: $0) }
                RadVerdi("Sum driftsinntekter", n.sumInntekter.kr, uthevet: true)
            } header: {
                Text("Driftsinntekter")
            }

            Section {
                if n.kostnader.isEmpty {
                    Text("Ingen kostnader i \(String(aar)).").foregroundStyle(.secondary)
                }
                ForEach(n.kostnader) { PostRad(post: $0) }
                RadVerdi("Sum driftskostnader", n.sumKostnader.kr, uthevet: true)
            } header: {
                Text("Driftskostnader")
            }

            Section {
                RadVerdi("Årsresultat", n.resultat.kr, uthevet: true)
            } footer: {
                Text("Kontonumrene er forslag etter standard kontoplan. Første gang er det lurt å sjekke dem mot veiledningen i skattemeldingen, eller la en regnskapsfører se over. Har du et overskudd, blir det automatisk personinntekt for deg.")
            }
        }
        .temaBakgrunn()
        .navigationTitle("Skattemelding \(String(aar))")
    }
}

private struct PostRad: View {
    let post: Naeringsspesifikasjon.Post

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(post.konto)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, alignment: .leading)
                Text(post.navn)
                Spacer()
                Text(post.belop.kr).monospacedDigit()
            }
            if let forklaring = post.forklaring {
                Text(forklaring)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 52)
            }
        }
    }
}
