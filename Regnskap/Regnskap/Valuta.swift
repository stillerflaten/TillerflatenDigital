import SwiftUI

/// Valutakurser fra Norges Bank. Kursen er hvor mange kroner én enhet av valutaen koster.
enum Valutakurs {
    static let valutaer = ["USD", "EUR", "GBP", "SEK", "DKK", "CHF", "JPY", "CAD", "AUD", "PLN"]

    static let kilde = URL(string: "https://www.norges-bank.no/tema/Statistikk/Valutakurser/")!

    struct Kurs: Equatable {
        /// Datoen kursen gjelder for, som «2026-10-16». Er det helg eller helligdag, er det siste bankdag før.
        let dato: String
        /// Kroner for én enhet av valutaen.
        let kroner: Double
    }

    enum Feil: LocalizedError {
        case ingenKurs
        var errorDescription: String? { "Norges Bank har ingen kurs for denne datoen." }
    }

    private static var hurtiglager: [String: Kurs] = [:]

    /// Dagen slik den vises i datovelgeren, altså i telefonens tidssone.
    static func datotekst(_ dato: Date) -> String {
        let d = Calendar.current.dateComponents([.year, .month, .day], from: dato)
        return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }

    /// Henter kursen for datoen. Finnes det ingen kurs den dagen, brukes siste kurs før.
    @MainActor
    static func hent(_ valuta: String, dato: Date) async throws -> Kurs {
        let til = datotekst(dato)
        let nokkel = "\(valuta) \(til)"
        if let kurs = hurtiglager[nokkel] { return kurs }

        // Ti dager bakover rekker over påske og jul.
        let fra = datotekst(Calendar.current.date(byAdding: .day, value: -10, to: dato) ?? dato)
        var url = URLComponents(string: "https://data.norges-bank.no/api/data/EXR/B.\(valuta).NOK.SP")!
        url.queryItems = [
            URLQueryItem(name: "format", value: "sdmx-json"),
            URLQueryItem(name: "startPeriod", value: fra),
            URLQueryItem(name: "endPeriod", value: til),
        ]
        let (data, svar) = try await URLSession.shared.data(from: url.url!)
        if let http = svar as? HTTPURLResponse, http.statusCode == 404 { throw Feil.ingenKurs }
        let kurs = try tolk(data, valuta: valuta)
        // Dagens kurs kommer først rundt kl. 16, så da lagres ikke gårsdagens.
        if kurs.dato == til { hurtiglager[nokkel] = kurs }
        return kurs
    }

    /// Leser svaret fra Norges Bank (SDMX-JSON) og plukker ut siste kurs.
    static func tolk(_ data: Data, valuta: String) throws -> Kurs {
        let svar = try JSONDecoder().decode(SdmxSvar.self, from: data)
        guard let serie = svar.data.dataSets.first?.series.values.first else { throw Feil.ingenKurs }
        let datoer = svar.data.structure.dimensions.observation.first?.values ?? []

        let siste = serie.observations
            .compactMap { nokkel, verdier -> (indeks: Int, kurs: Double)? in
                guard let i = Int(nokkel), let kurs = verdier.first??.tall else { return nil }
                return (i, kurs)
            }
            .max { $0.indeks < $1.indeks }
        guard let siste, siste.indeks < datoer.count else { throw Feil.ingenKurs }

        // Noen valutaer (SEK, DKK, JPY m.fl.) oppgis per 100. Det står i UNIT_MULT.
        var multiplikator = ["SEK", "DKK", "JPY"].contains(valuta) ? 2 : 0
        if let i = svar.data.structure.attributes.series.firstIndex(where: { $0.id == "UNIT_MULT" }),
           i < serie.attributes.count, let verdiIndeks = serie.attributes[i],
           verdiIndeks < svar.data.structure.attributes.series[i].values.count,
           let m = Int(svar.data.structure.attributes.series[i].values[verdiIndeks].id) {
            multiplikator = m
        }
        let kroner = siste.kurs / pow(10, Double(multiplikator))
        return Kurs(dato: datoer[siste.indeks].id, kroner: kroner)
    }

    // Bare de delene av SDMX-JSON vi trenger.
    private struct SdmxSvar: Decodable {
        let data: Innhold
        struct Innhold: Decodable {
            let dataSets: [Datasett]
            let structure: Struktur
        }
        struct Datasett: Decodable {
            let series: [String: Serie]
        }
        struct Serie: Decodable {
            let attributes: [Int?]
            let observations: [String: [TallEllerTekst?]]
        }
        struct Struktur: Decodable {
            let dimensions: Dimensjoner
            let attributes: Attributter
        }
        struct Dimensjoner: Decodable {
            let observation: [Dimensjon]
        }
        struct Attributter: Decodable {
            let series: [Dimensjon]
        }
        struct Dimensjon: Decodable {
            let id: String
            let values: [Verdi]
        }
        struct Verdi: Decodable {
            let id: String
        }
    }

    /// Norges Bank sender kursen som tekst («10.8475»), men vi tåler tall også.
    private struct TallEllerTekst: Decodable {
        let tall: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { tall = d }
            else if let s = try? c.decode(String.self) { tall = Double(s) }
            else { tall = nil }
        }
    }
}

struct ValutakalkulatorView: View {
    @State private var belop: Double = 0
    @State private var valuta = "USD"
    @State private var dato = Date.now
    @State private var tilKroner = true
    @State private var kurs: Valutakurs.Kurs?
    @State private var feil: String?
    @State private var henter = false
    @State private var forsok = 0

    private static let norsk = Locale(identifier: "nb_NO")

    private var resultat: Double? {
        guard let kurs, kurs.kroner > 0 else { return nil }
        return tilKroner ? belop * kurs.kroner : belop / kurs.kroner
    }

    var body: some View {
        Form {
            Section {
                Picker("Regn om", selection: $tilKroner) {
                    Text("Til kroner").tag(true)
                    Text("Fra kroner").tag(false)
                }
                .pickerStyle(.segmented)
                BelopFelt("Beløp", belop: $belop, enhet: tilKroner ? valuta : "kr")
                Picker("Valuta", selection: $valuta) {
                    ForEach(Valutakurs.valutaer, id: \.self) { kode in
                        Text("\(kode) – \(Self.norsk.localizedString(forCurrencyCode: kode) ?? kode)").tag(kode)
                    }
                }
                DatePicker("Dato", selection: $dato, in: ...Date.now, displayedComponents: .date)
            } footer: {
                Text("Velg datoen du betalte eller fikk pengene, så får du kursen fra den dagen.")
            }

            Section("Resultat") {
                if let kurs, let resultat {
                    RadVerdi(tilKroner ? "I kroner" : "I \(valuta)", Self.vis(resultat, kode: tilKroner ? "NOK" : valuta), uthevet: true)
                    RadVerdi("Kurs \(Self.kortDato(kurs.dato))", "1 \(valuta) = \(kurs.kroner.formatted(.number.precision(.fractionLength(2...4)).locale(Self.norsk))) kr")
                    if kurs.dato != Valutakurs.datotekst(dato) {
                        Text("Det finnes ingen kurs for den dagen ennå (helg, helligdag eller før kl. 16), så siste kurs før er brukt.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if henter {
                    HStack {
                        Text("Henter kurs …")
                        Spacer()
                        ProgressView()
                    }
                } else if let feil {
                    Label(feil, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                    Button("Prøv igjen") { forsok += 1 }
                }
            }

            Section {
                Text("Kursene er Norges Banks offisielle midtkurser. Har du betalt med kort, står det beløpet som faktisk ble trukket i kroner på kontoutskriften. Det er det beløpet du skal føre.")
                Link(destination: Valutakurs.kilde) {
                    Label("Valutakurser hos Norges Bank", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Om kursene")
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle("Valuta")
        .task(id: "\(valuta) \(Valutakurs.datotekst(dato)) \(forsok)") { await hentKurs() }
    }

    private func hentKurs() async {
        henter = true
        feil = nil
        kurs = nil
        let (v, d) = (valuta, Valutakurs.datotekst(dato))
        do {
            let ny = try await Valutakurs.hent(v, dato: dato)
            // Har du byttet valuta eller dato i mellomtiden, hører svaret til et gammelt valg.
            guard !Task.isCancelled, v == valuta, d == Valutakurs.datotekst(dato) else { return }
            kurs = ny
        } catch is CancellationError {
            return
        } catch let f as Valutakurs.Feil {
            feil = f.errorDescription
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            feil = "Fikk ikke hentet kursen. Sjekk at du er på nett."
        }
        henter = false
    }

    private static func vis(_ verdi: Double, kode: String) -> String {
        verdi.formatted(.currency(code: kode).precision(.fractionLength(2)).locale(norsk))
    }

    /// «2026-10-16» → «16. okt. 2026»
    private static func kortDato(_ tekst: String) -> String {
        let deler = tekst.split(separator: "-").compactMap { Int($0) }
        guard deler.count == 3,
              let d = Frister.kalender.date(from: DateComponents(year: deler[0], month: deler[1], day: deler[2]))
        else { return tekst }
        return d.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: Frister.kalender.timeZone).locale(norsk))
    }
}
