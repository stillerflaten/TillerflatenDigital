import SwiftUI

struct InnstillingerView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Innstilling.lonn) private var lonn: Double = 0
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false
    @AppStorage(Innstilling.mvaAarstermin) private var mvaAarstermin = false
    @AppStorage(Innstilling.forskuddsskatt) private var forskuddsskatt = true
    @AppStorage(Innstilling.hjemmekontor) private var hjemmekontor = false

    var body: some View {
        NavigationStack {
            Form {
                SikkerhetskopiSeksjon()

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
                    if mvaRegistrert {
                        Toggle("Årstermin (én mva-melding i året)", isOn: $mvaAarstermin)
                    }
                } header: {
                    Text("Merverdiavgift")
                } footer: {
                    Text("Når du er mva-registrert, trekkes mva fra i utgiftene (du får den tilbake), og appen viser mva-frister.")
                }

                Section {
                    Toggle("Eget rom brukt som hjemmekontor", isOn: $hjemmekontor)
                } footer: {
                    Text("Gir et standardfradrag på \(Skattesatser.aar2026.hjemmekontorSjablong.kr) i året. Rommet må bare brukes til jobb i foretaket. Har du høyere dokumenterte kostnader, kan du heller trekke fra dem.")
                }
            }
            .temaBakgrunn()
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

/// Tekstfelt for kronebeløp med tallastatur.
struct BelopFelt: View {
    let tittel: String
    @Binding var belop: Double

    init(_ tittel: String, belop: Binding<Double>) {
        self.tittel = tittel
        self._belop = belop
    }

    var body: some View {
        HStack {
            Text(tittel)
            Spacer()
            TextField("0", value: $belop, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 160)
            Text("kr")
                .foregroundStyle(.secondary)
        }
    }
}
