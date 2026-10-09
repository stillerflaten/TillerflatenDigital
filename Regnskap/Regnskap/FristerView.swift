import SwiftUI

struct FristerView: View {
    @AppStorage(Innstilling.forskuddsskatt) private var forskuddsskatt = true
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false
    @AppStorage(Innstilling.mvaAarstermin) private var mvaAarstermin = false
    @AppStorage(Innstilling.varsler) private var varsler = false
    @AppStorage(Innstilling.varselDagerFor) private var dagerFor = 7

    @State private var iKalender: Set<String> = []
    @State private var kalenderMelding: String?

    private var frister: [Frist] {
        Frister.kommende(forskuddsskatt: forskuddsskatt, mvaRegistrert: mvaRegistrert, mvaAarstermin: mvaAarstermin)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Varsle meg før frister", isOn: $varsler)
                    if varsler {
                        Stepper("\(dagerFor) dager før", value: $dagerFor, in: 1...30)
                    }
                } footer: {
                    Text("Varselet kommer kl. 09.00. Frister som havner i helg, er flyttet til mandag. Sjekk helligdager selv.")
                }

                Section {
                    Button {
                        Task { await leggAlleIKalender() }
                    } label: {
                        Label("Legg alle fristene i kalenderen", systemImage: "calendar.badge.plus")
                    }
                } footer: {
                    Text("Fristene havner i en egen kalender som heter «\(Kalender.navn)», med varsel kl. 09.00 \(dagerFor) dager før. Trykker du flere ganger, oppdateres de som finnes, i stedet for å legges inn på nytt.")
                }

                Section {
                    ForEach(frister) { frist in
                        FristRad(frist: frist, iKalender: iKalender.contains("frist-\(frist.id)"))
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await leggIKalender([frist]) }
                                } label: {
                                    Label("Kalender", systemImage: "calendar.badge.plus")
                                }
                                .tint(Color.accentColor)
                            }
                            .contextMenu {
                                Button("Legg i kalenderen", systemImage: "calendar.badge.plus") {
                                    Task { await leggIKalender([frist]) }
                                }
                            }
                    }
                } header: {
                    Text("Kommende frister")
                } footer: {
                    Text("Sveip til høyre på en frist for å legge bare den i kalenderen.")
                }

                Section {
                    Link("Forskuddsskatt hos Skatteetaten", destination: Kilder.forskuddsskatt)
                } footer: {
                    Text("Datoene er hentet fra Skatteetaten høsten 2026. Skatteetaten kan endre frister, så dobbeltsjekk der.")
                }
            }
            .temaBakgrunn()
            .navigationTitle("Frister")
            .onChange(of: varsler) { _, paa in
                if paa {
                    Task {
                        if await Varsler.beOmTillatelse() {
                            planlegg()
                        } else {
                            varsler = false
                        }
                    }
                } else {
                    Varsler.fjernAlleFrister()
                }
            }
            .onChange(of: dagerFor) { planlegg() }
            .onChange(of: forskuddsskatt) { planlegg() }
            .onChange(of: mvaRegistrert) { planlegg() }
            .onChange(of: mvaAarstermin) { planlegg() }
            .onAppear {
                planlegg()
                oppdaterKalenderstatus()
            }
            .alert("Kalender", isPresented: Binding(get: { kalenderMelding != nil }, set: { if !$0 { kalenderMelding = nil } })) {
                Button("OK") { kalenderMelding = nil }
            } message: {
                Text(kalenderMelding ?? "")
            }
        }
    }

    private func leggAlleIKalender() async {
        await leggIKalender(frister)
    }

    private func leggIKalender(_ utvalg: [Frist]) async {
        guard await Kalender.beOmTilgang() else {
            kalenderMelding = Kalender.Feil.ingenTilgang.errorDescription
            return
        }
        do {
            for frist in utvalg {
                try Kalender.leggInn(frist, dagerFor: dagerFor)
            }
            oppdaterKalenderstatus()
            kalenderMelding = utvalg.count == 1
                ? "«\(utvalg[0].tittel)» er lagt i kalenderen."
                : "\(utvalg.count) frister er lagt i kalenderen «\(Kalender.navn)»."
        } catch {
            kalenderMelding = "Kunne ikke legge inn i kalenderen: \(error.localizedDescription)"
        }
    }

    private func oppdaterKalenderstatus() {
        guard let siste = frister.last?.dato else { return }
        let start = Frister.kalender.startOfDay(for: .now)
        let slutt = Frister.kalender.date(byAdding: .day, value: 2, to: siste) ?? siste
        iKalender = Kalender.lagtInn(fra: start, til: slutt)
    }

    private func planlegg() {
        guard varsler else { return }
        Varsler.planleggFrister(frister, dagerFor: dagerFor)
    }
}

struct FristRad: View {
    let frist: Frist
    var iKalender = false

    private var dagerIgjen: Int {
        let cal = Frister.kalender
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: frist.dato)).day ?? 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: frist.ikon)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(frist.tittel)
                    if iKalender {
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Lagt i kalenderen")
                    }
                }
                Text(frist.forklaring)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(frist.dato.formatted(.dateTime.day().month(.abbreviated)))
                    .fontWeight(.medium)
                Text(dagerIgjen == 0 ? "i dag" : "om \(dagerIgjen) d")
                    .font(.caption)
                    .foregroundStyle(dagerIgjen <= 7 ? Color.orange : Color.secondary)
            }
        }
    }
}
