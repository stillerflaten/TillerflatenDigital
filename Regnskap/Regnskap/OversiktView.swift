import SwiftUI
import SwiftData

struct OversiktView: View {
    @Query(sort: \Bilag.dato, order: .reverse) private var bilag: [Bilag]
    @Query(sort: \Inntekt.dato, order: .reverse) private var inntekter: [Inntekt]
    @Query private var driftsmidler: [Driftsmiddel]
    @Query private var turer: [Kjoretur]
    @Query(sort: \Faktura.forfallsdato) private var fakturaer: [Faktura]

    @AppStorage(Innstilling.lonn) private var lonn: Double = 0
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false
    @AppStorage(Innstilling.hjemmekontor) private var hjemmekontor = false
    @AppStorage(Innstilling.forskuddsskatt) private var forskuddsskatt = true
    @AppStorage(Innstilling.mvaAarstermin) private var mvaAarstermin = false

    @State private var aar = Date.now.aar
    @State private var visInnstillinger = false

    private var oversikt: Aarsoversikt {
        Aarsoversikt(aar: aar, bilag: bilag, inntekter: inntekter, driftsmidler: driftsmidler, turer: turer,
                     lonn: lonn, mvaRegistrert: mvaRegistrert, hjemmekontor: hjemmekontor)
    }

    private var ubetalte: [Bilag] {
        bilag.filter { $0.erRegning && !$0.erBetalt }
            .sorted { ($0.forfallsdato ?? .distantFuture) < ($1.forfallsdato ?? .distantFuture) }
    }

    private var aarSomKanVelges: [Int] {
        let iAar = Date.now.aar
        let alle = Set(bilag.map(\.dato.aar) + inntekter.map(\.dato.aar) + [iAar])
        return alle.sorted(by: >)
    }

    var body: some View {
        let o = oversikt
        NavigationStack {
            List {
                if lonn == 0 {
                    Section {
                        Button {
                            visInnstillinger = true
                        } label: {
                            Label("Legg inn lønnen din fra politiet for å få riktig skatteberegning", systemImage: "exclamationmark.circle")
                        }
                    }
                }

                Section {
                    HeroKort {
                        HStack(spacing: 8) {
                            Logomerke()
                                .fill(Color.temaFjell)
                                .frame(width: 22, height: 22)
                            Text("REGNSKAP \(String(aar))")
                                .font(.caption.weight(.semibold))
                                .tracking(1.2)
                                .foregroundStyle(Color.temaHeroDempet)
                        }
                        .padding(.bottom, 6)
                        Text("Sett av til skatt")
                            .font(.subheadline)
                            .foregroundStyle(Color.temaHeroDempet)
                        Text(max(0, o.skatt.ekstraSkatt).kr)
                            .font(.tittel(.largeTitle))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if o.overskudd > 0 {
                            Text("Ca. \(o.skatt.andel(av: o.overskudd).prosent) av overskuddet. Neste krone skattes med \(o.skatt.marginalsats.prosent).")
                                .font(.footnote)
                                .foregroundStyle(Color.temaHeroDempet)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    RadVerdi("Inntekter", o.inntekter.kr)
                    RadVerdi("Fradrag", "−" + o.fradrag.kr)
                    RadVerdi("Overskudd", o.overskudd.kr, uthevet: true)
                } header: {
                    Text("Resultat")
                } footer: {
                    if !Skattesatser.erEksakt(for: aar) {
                        Text("Beregnet med 2026-satser. Satsene for \(String(aar)) er ikke lagt inn ennå.")
                    }
                }

                Section("Fradrag i \(String(aar))") {
                    RadVerdi("Utgifter (bilag)", o.utgifter.kr)
                    RadVerdi("Avskrivning av utstyr", o.avskrivninger.kr)
                    if o.kjoreKm > 0 {
                        RadVerdi("Kjøring (\(Int(o.kjoreKm)) km)", o.kjorefradrag.kr)
                    }
                    if o.hjemmekontor > 0 {
                        RadVerdi("Hjemmekontor (sjablong)", o.hjemmekontor.kr)
                    }
                    if mvaRegistrert {
                        RadVerdi("Inngående mva (får du tilbake)", o.inngaendeMva.kr)
                    }
                }

                if !mvaRegistrert {
                    Section {
                        MvaGrenseView(inntekter: inntekter)
                    } header: {
                        Text("Mva-grensen")
                    }
                }

                let utestaende = fakturaer.filter { $0.status == .sendt }
                if !utestaende.isEmpty {
                    Section("Fakturaer som venter på betaling") {
                        ForEach(utestaende) { f in
                            NavigationLink {
                                FakturaView(faktura: f)
                            } label: {
                                FakturaRad(faktura: f)
                            }
                        }
                    }
                }

                if !ubetalte.isEmpty {
                    Section("Ubetalte regninger") {
                        ForEach(ubetalte) { regning in
                            NavigationLink {
                                BilagSkjemaView(bilag: regning)
                            } label: {
                                RegningRad(regning: regning)
                            }
                        }
                    }
                }

                if let neste = Frister.kommende(forskuddsskatt: forskuddsskatt, mvaRegistrert: mvaRegistrert,
                                                mvaAarstermin: mvaAarstermin).first {
                    Section("Neste frist") {
                        FristRad(frist: neste)
                    }
                }

                Section {
                    NavigationLink {
                        ArkivView()
                    } label: {
                        Label("Arkiv med alle år", systemImage: "archivebox")
                    }
                    ShareLink(item: Eksport.csvFil(aar: aar, bilag: bilag, inntekter: inntekter, mvaRegistrert: mvaRegistrert),
                              preview: SharePreview("Regnskap \(String(aar)).csv")) {
                        Label("Eksporter \(String(aar)) som regneark (CSV)", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("Fint å sende til regnskapsfører, eller å ha for hånden når du fyller ut skattemeldingen. Tallene er estimater, ikke et ferdig regnskap.")
                }
            }
            .temaBakgrunn()
            .navigationTitle("Tillerflaten Digital")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("År", selection: $aar) {
                            ForEach(aarSomKanVelges, id: \.self) { Text(String($0)).tag($0) }
                        }
                    } label: {
                        Label(String(aar), systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        visInnstillinger = true
                    } label: {
                        Label("Innstillinger", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $visInnstillinger) {
                InnstillingerView()
            }
        }
    }
}

/// Viser hvor nær du er grensen på 50 000 kr for mva-registrering, siste 12 måneder.
struct MvaGrenseView: View {
    let inntekter: [Inntekt]

    private var siste12: Double {
        let fra = Calendar.current.date(byAdding: .month, value: -12, to: .now) ?? .now
        return inntekter.filter { $0.dato >= fra }.reduce(0) { $0 + $1.belop }
    }

    var body: some View {
        let grense = Skattesatser.aar2026.mvaRegistreringsgrense
        let andel = min(1, siste12 / grense)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Siste 12 måneder")
                Spacer()
                Text("\(siste12.kr) av \(grense.kr)")
                    .monospacedDigit()
            }
            ProgressView(value: andel)
                .tint(andel >= 1 ? Color.red : andel > 0.8 ? Color.orange : Color.accentColor)
            Text(andel >= 1
                 ? "Du har passert grensen og skal registrere deg i Merverdiavgiftsregisteret. Se Kalkulatorer → Mva."
                 : "Når omsetningen passerer 50 000 kr i løpet av 12 måneder, må du registrere foretaket for mva.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct RadVerdi: View {
    let tittel: String
    let verdi: String
    var uthevet = false

    init(_ tittel: String, _ verdi: String, uthevet: Bool = false) {
        self.tittel = tittel
        self.verdi = verdi
        self.uthevet = uthevet
    }

    var body: some View {
        HStack {
            Text(tittel)
            Spacer()
            Text(verdi)
                .monospacedDigit()
                .foregroundStyle(uthevet ? .primary : .secondary)
        }
        .fontWeight(uthevet ? .semibold : .regular)
    }
}

struct RegningRad: View {
    let regning: Bilag

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(regning.tittel.isEmpty ? "Regning" : regning.tittel)
                if let forfall = regning.forfallsdato {
                    Text("Forfaller \(forfall.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(forfall < .now ? Color.red : Color.secondary)
                }
            }
            Spacer()
            Text(regning.belop.kr)
                .monospacedDigit()
        }
    }
}
