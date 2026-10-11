import SwiftUI
import SwiftData

struct MvaView: View {
    @Query private var inntekter: [Inntekt]
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false

    var body: some View {
        List {
            if mvaRegistrert {
                Section {
                    NavigationLink {
                        MvaMeldingView()
                    } label: {
                        Label("Tall til mva-meldingen", systemImage: "doc.text.magnifyingglass")
                    }
                }
            } else {
                Section {
                    MvaGrenseView(inntekter: inntekter)
                }
            }

            Section("Når må jeg registrere meg?") {
                Text("Når salget passerer 50 000 kr i løpet av 12 måneder, skal foretaket registreres i Merverdiavgiftsregisteret. Både App Store-inntekter og nettsideoppdrag teller med.")
                Text("Du kan registrere deg når du passerer grensen. Fakturaer du sender etter at registreringen er godkjent, skal ha 25 % mva.")
            }

            Section("App Store") {
                Text("Når noen kjøper appen din, er det Apple som selger den til kunden og betaler mva der kunden bor. Du selger i praksis en tjeneste til Apple, som holder til i utlandet.")
                Text("Det er fritatt for norsk mva. Du legger altså ikke 25 % mva på det Apple betaler deg, og i mva-meldingen føres det som tjenester til utlandet.")
            }

            Section("Nettsider og andre oppdrag i Norge") {
                Text("Lager du nettsider for norske kunder, er det vanlig salg med 25 % mva. Så lenge du ikke er registrert, sender du fakturaer uten mva.")
                Text("Når du er registrert, legger appen på 25 % mva på nye fakturaer. Kunden betaler mva-en til deg, og du betaler den videre til staten i mva-meldingen.")
            }

            Section("Hva betyr det å være mva-registrert?") {
                Label("Du får tilbake mva på det du kjøper i Norge til foretaket, f.eks. 25 % av prisen på en ny Mac.", systemImage: "plus.circle")
                Label("Du må levere mva-melding seks ganger i året, eller én gang i året hvis omsetningen er lav og Skatteetaten godkjenner årstermin.", systemImage: "minus.circle")
                Label("Kjøper du tjenester fra utlandet (Apple Developer, GitHub, Claude osv.), beregner du selv norsk mva av dem («omvendt avgiftsplikt»), og trekker den fra igjen samtidig. Merk slike bilag med «Kjøpt fra utlandet».", systemImage: "arrow.left.arrow.right.circle")
            }

            Section {
                Link("Registrering i Merverdiavgiftsregisteret (Skatteetaten)", destination: Kilder.mva)
            } footer: {
                Text("Usikker? Ring Skatteetaten (800 80 000) eller spør en regnskapsfører før du registrerer deg.")
            }
        }
        .temaBakgrunn()
        .navigationTitle("Mva")
    }
}

/// Tallene til mva-meldingen for én termin.
struct MvaMeldingView: View {
    @Query private var bilag: [Bilag]
    @Query private var inntekter: [Inntekt]
    @Query private var fakturaer: [Faktura]
    @AppStorage(Innstilling.mvaAarstermin) private var aarstermin = false

    @State private var termin = Mva.Termin.gjeldende(aarstermin: false)

    private var valg: [Mva.Termin] {
        let iAar = Date.now.aar
        return (Mva.Termin.alle(aar: iAar, aarstermin: aarstermin) + Mva.Termin.alle(aar: iAar - 1, aarstermin: aarstermin))
            .filter { $0.fra <= .now }
            .sorted { $0.fra > $1.fra }
    }

    var body: some View {
        let m = MvaMelding(termin: termin, bilag: bilag, inntekter: inntekter, fakturaer: fakturaer)
        List {
            Section {
                Picker("Periode", selection: $termin) {
                    ForEach(valg) { Text($0.navn).tag($0) }
                }
            }

            Section {
                KodeRad(kode: "3", tekst: "Salg i Norge, 25 %", grunnlag: m.salgGrunnlag, mva: m.salgMva)
                KodeRad(kode: "52", tekst: "Tjenester til utlandet, fritatt (App Store)", grunnlag: m.fritattUtland, mva: nil)
                KodeRad(kode: "86", tekst: "Tjenester kjøpt fra utlandet", grunnlag: m.utlandGrunnlag, mva: m.utlandBeregnet)
            } header: {
                Text("Utgående mva")
            } footer: {
                Text("Salg regnes etter fakturadatoen, ikke når kunden betaler.")
            }

            Section {
                KodeRad(kode: "1", tekst: "Fradrag for kjøp i Norge", grunnlag: nil, mva: m.inngaendeMva)
                KodeRad(kode: "86", tekst: "Fradrag for kjøp fra utlandet", grunnlag: nil, mva: m.utlandFradrag)
            } header: {
                Text("Inngående mva (fradrag)")
            }

            Section {
                RadVerdi(m.aaBetale >= 0 ? "Å betale" : "Til gode", abs(m.aaBetale).kr, uthevet: true)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if m.ukjenteInntekter != 0 {
                        Text("\(m.ukjenteInntekter.kr) i inntekter lagt inn for hånd er ikke med, fordi appen ikke vet om de har mva. Legg dem til selv.")
                    }
                    Text("Mva-meldingen leveres i Altinn eller regnskapsprogrammet ditt. Kodene over er de samme som der. Sjekk tallene før du sender.")
                }
            }
        }
        .temaBakgrunn()
        .navigationTitle("Mva-melding")
        .onAppear {
            if !valg.contains(termin) { termin = valg.first ?? Mva.Termin.gjeldende(aarstermin: aarstermin) }
        }
    }
}

private struct KodeRad: View {
    let kode: String
    let tekst: String
    let grunnlag: Double?
    let mva: Double?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(kode)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(tekst)
                if let grunnlag {
                    Text("Grunnlag \(grunnlag.kr)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let mva {
                Text(mva.kr).monospacedDigit()
            }
        }
    }
}

struct SjekklisteView: View {
    @AppStorage("sjekkliste.ferdig") private var ferdigRaw = ""

    private struct Punkt: Identifiable {
        let id: String
        let tittel: String
        let forklaring: String
    }

    private let punkter: [Punkt] = [
        Punkt(id: "registrer", tittel: "Registrer foretaket",
              forklaring: "Samordnet registermelding i Altinn. Gratis for ENK i Enhetsregisteret. Du får et organisasjonsnummer."),
        Punkt(id: "bierverv", tittel: "Godkjent bierverv",
              forklaring: "Du har allerede fått godkjent bierverv. Ta vare på godkjenningen, og meld fra hvis aktiviteten endrer seg vesentlig."),
        Punkt(id: "bank", tittel: "Egen bankkonto for foretaket",
              forklaring: "Ikke påkrevd for ENK, men gjør regnskapet mye enklere. La Apple betale inn hit, og betal utgifter herfra."),
        Punkt(id: "apple", tittel: "Bytt Apple-utbetalingene til foretaket",
              forklaring: "Oppdater bankkonto og skatteinformasjon i App Store Connect (Agreements, Tax, and Banking)."),
        Punkt(id: "forskudd", tittel: "Bestill forskuddsskatt",
              forklaring: "Legg inn forventet overskudd på skatteetaten.no, så slipper du restskatt. Bruk skattekalkulatoren i appen."),
        Punkt(id: "bilag", tittel: "Ta vare på alle bilag i 5 år",
              forklaring: "Kvitteringer, fakturaer og Apples utbetalingsrapporter. Last ned månedsrapportene fra App Store Connect."),
        Punkt(id: "mva", tittel: "Følg med på mva-grensen",
              forklaring: "Registrer deg når omsetningen passerer 50 000 kr i løpet av 12 måneder."),
        Punkt(id: "skattemelding", tittel: "Skattemelding for næringsdrivende",
              forklaring: "Leveres innen 31. mai året etter, med næringsspesifikasjon. Den må leveres aktivt, den godkjennes ikke automatisk slik som for lønnsmottakere."),
        Punkt(id: "forsikring", tittel: "Vurder forsikring og sykepenger",
              forklaring: "Næringsinntekten har svakere sykepengedekning enn lønn (80 % fra dag 17). Lønnen i politiet dekkes som før, så for et lite bierverv er dette sjelden noe stort problem."),
        Punkt(id: "regnskapsforer", tittel: "Vurder regnskapsfører det første året",
              forklaring: "Koster noen tusenlapper, er fradragsberettiget, og gir trygghet for at skattemeldingen blir riktig."),
    ]

    private var ferdig: Set<String> {
        Set(ferdigRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        List(punkter) { punkt in
            Button {
                var ny = ferdig
                if ny.contains(punkt.id) { ny.remove(punkt.id) } else { ny.insert(punkt.id) }
                ferdigRaw = ny.sorted().joined(separator: ",")
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: ferdig.contains(punkt.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(ferdig.contains(punkt.id) ? Color.green : Color.secondary)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(punkt.tittel)
                            .strikethrough(ferdig.contains(punkt.id))
                        Text(punkt.forklaring)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .temaBakgrunn()
        .navigationTitle("Sjekkliste")
    }
}
