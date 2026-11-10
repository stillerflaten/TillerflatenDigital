import SwiftUI
import QuickLook

struct InnstillingerView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Innstilling.lonn) private var lonn: Double = 0
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false
    @AppStorage(Innstilling.mvaAarstermin) private var mvaAarstermin = false
    @AppStorage(Innstilling.forskuddsskatt) private var forskuddsskatt = true
    @AppStorage(Innstilling.hjemmekontor) private var hjemmekontor = false
    @AppStorage(Innstilling.mvaFra) private var mvaFra: Double = 0
    @AppStorage(Innstilling.laas) private var laas = false
    @State private var manual: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        manual = Brukermanual.url
                    } label: {
                        Label("Brukermanual", systemImage: "book")
                    }
                } footer: {
                    Text("Slik bruker du appen, steg for steg. Du finner den også under spørsmålstegnet på Oversikt.")
                }

                SikkerhetskopiSeksjon()

                if Laas.stottes {
                    Section {
                        Toggle("Lås med \(Laas.metode)", isOn: $laas)
                    } footer: {
                        Text("Appen låses når du går ut av den, og må låses opp med \(Laas.metode) når du kommer tilbake. Gjelder bare denne enheten.")
                    }
                }

                Section {
                    NavigationLink {
                        FirmaView()
                    } label: {
                        Label("Firmaopplysninger til fakturaer", systemImage: "building.2")
                    }
                }

                Section {
                    BelopFelt("Brutto årslønn", belop: $lonn)
                } header: {
                    Text("Lønn fra fast jobb")
                } footer: {
                    Text("Lønnen avgjør hvor høy trinnskatt overskuddet fra foretaket får. Bruk forventet brutto årslønn inkludert tillegg (se lønnsslippen eller skattekortet).")
                }

                Section {
                    Toggle("Jeg betaler forskuddsskatt", isOn: $forskuddsskatt)
                } footer: {
                    Text("Som næringsdrivende betaler du skatten av overskuddet selv, fire ganger i året. Du endrer beløpet på skatteetaten.no når du vet mer om hva du tjener.")
                }

                Section {
                    Toggle("Foretaket er mva-registrert", isOn: $mvaRegistrert)
                        .onChange(of: mvaRegistrert) { _, paa in
                            if paa && mvaFra == 0 { mvaFra = Frister.kalender.startOfDay(for: .now).timeIntervalSince1970 }
                        }
                    if mvaRegistrert {
                        if mvaFra > 0 {
                            DatePicker("Registrert fra", selection: Binding(
                                get: { Date(timeIntervalSince1970: mvaFra) },
                                set: { mvaFra = $0.timeIntervalSince1970 }
                            ), displayedComponents: .date)
                        } else {
                            HStack {
                                Text("Registrert fra")
                                Spacer()
                                Button("Velg dato") {
                                    mvaFra = Frister.kalender.startOfDay(for: .now).timeIntervalSince1970
                                }
                            }
                        }
                        Toggle("Årstermin (én mva-melding i året)", isOn: $mvaAarstermin)
                    }
                } header: {
                    Text("Merverdiavgift")
                } footer: {
                    Text(mvaRegistrert
                         ? "Mva på kvitteringer fra og med denne datoen trekkes fra (du får den tilbake). Nye fakturaer får 25 % mva, og appen viser mva-frister og tall til mva-meldingen."
                         : "Når du er mva-registrert, trekkes mva fra i utgiftene (du får den tilbake), og appen viser mva-frister.")
                }

                Section {
                    Toggle("Eget rom brukt som hjemmekontor", isOn: $hjemmekontor)
                } footer: {
                    Text("Gir et standardfradrag på \(Skattesatser.aar2026.hjemmekontorSjablong.kr) i året. Rommet må bare brukes til jobb i foretaket. Har du høyere dokumenterte kostnader, kan du heller trekke fra dem.")
                }
            }
            .temaBakgrunn()
            .quickLookPreview($manual)
            .navigationTitle("Innstillinger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
    }
}

// BelopFelt (beløpsfelt med kalkulator) ligger i Kalkulator.swift.

/// Brukermanualen ligger i appen som PDF. Kilden er Regnskap/Manual/Brukermanual-Regnskap.html.
enum Brukermanual {
    static var url: URL? { Bundle.main.url(forResource: "Brukermanual-Regnskap", withExtension: "pdf") }
}
