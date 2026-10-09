import SwiftUI
import SwiftData

struct MvaView: View {
    @Query private var inntekter: [Inntekt]
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false

    var body: some View {
        List {
            if !mvaRegistrert {
                Section {
                    MvaGrenseView(inntekter: inntekter)
                }
            }

            Section("Hvordan App Store fungerer") {
                Text("Når noen kjøper appen din, er det Apple som selger den til kunden. Apple krever inn og betaler mva til Norge og andre land. Du selger i praksis en tjeneste til Apple, som holder til i utlandet.")
                Text("Salg av slike tjenester til en bedrift i utlandet er fritatt for norsk mva (null-sats). Du legger altså ikke 25 % mva på det Apple betaler deg.")
                Text("Fritatt omsetning teller likevel med når du regner om du har passert 50 000 kr. Passerer du grensen, skal foretaket registreres i Merverdiavgiftsregisteret.")
            }

            Section("Hva betyr det å være mva-registrert?") {
                Label("Du får tilbake mva på utstyr og annet du kjøper i Norge, f.eks. 25 % av prisen på en ny Mac.", systemImage: "plus.circle")
                Label("Du må levere mva-melding (vanligvis seks ganger i året, eller én gang i året ved lav omsetning).", systemImage: "minus.circle")
                Label("Kjøper du tjenester fra utlandet (Apple Developer, GitHub, Claude osv.), må du selv beregne norsk mva av dem («omvendt avgiftsplikt»), men kan som regel trekke den fra igjen samtidig.", systemImage: "arrow.left.arrow.right.circle")
            }

            Section {
                Link("Registrering i Merverdiavgiftsregisteret (Skatteetaten)", destination: Kilder.mva)
            } footer: {
                Text("Mva for app-utviklere har noen spesielle regler. Ring gjerne Skatteetaten (800 80 000) eller spør en regnskapsfører før du registrerer deg, så du er sikker.")
            }
        }
        .temaBakgrunn()
        .navigationTitle("Mva")
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
