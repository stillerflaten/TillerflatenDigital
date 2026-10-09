import SwiftUI

struct FristerView: View {
    @AppStorage(Innstilling.forskuddsskatt) private var forskuddsskatt = true
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false
    @AppStorage(Innstilling.mvaAarstermin) private var mvaAarstermin = false
    @AppStorage(Innstilling.varsler) private var varsler = false
    @AppStorage(Innstilling.varselDagerFor) private var dagerFor = 7

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

                Section("Kommende frister") {
                    ForEach(frister) { frist in
                        FristRad(frist: frist)
                    }
                }

                Section {
                    Link("Forskuddsskatt hos Skatteetaten", destination: Kilder.forskuddsskatt)
                } footer: {
                    Text("Datoene er hentet fra Skatteetaten høsten 2026. Skatteetaten kan endre frister, så dobbeltsjekk der.")
                }
            }
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
            .onAppear { planlegg() }
        }
    }

    private func planlegg() {
        guard varsler else { return }
        Varsler.planleggFrister(frister, dagerFor: dagerFor)
    }
}

struct FristRad: View {
    let frist: Frist

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
                Text(frist.tittel)
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
