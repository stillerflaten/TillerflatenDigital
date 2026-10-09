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

/// Tekstfelt for beløp med tallastatur. Feltet er tomt når beløpet er 0,
/// så du kan skrive rett inn uten å måtte slette en null først.
struct BelopFelt: View {
    let tittel: String
    @Binding var belop: Double
    let enhet: String

    @State private var tekst = ""
    @FocusState private var iFokus: Bool

    init(_ tittel: String, belop: Binding<Double>, enhet: String = "kr") {
        self.tittel = tittel
        self._belop = belop
        self.enhet = enhet
    }

    var body: some View {
        HStack {
            Text(tittel)
            Spacer()
            TextField("0", text: $tekst)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 160)
                .focused($iFokus)
            Text(enhet)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { iFokus = true }
        .onAppear { tekst = Self.vis(belop) }
        .onChange(of: tekst) { _, ny in
            belop = Self.tolk(ny)
        }
        .onChange(of: belop) { _, ny in
            // Beløpet kan endres utenfra. Ikke forstyrr mens du skriver.
            if !iFokus && Self.tolk(tekst) != ny { tekst = Self.vis(ny) }
        }
        .onChange(of: iFokus) { _, fokus in
            if !fokus { tekst = Self.vis(belop) }
        }
    }

    private static func vis(_ verdi: Double) -> String {
        verdi == 0 ? "" : verdi.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Godtar både komma og punktum, og hopper over mellomrom (tusenskille).
    private static func tolk(_ tekst: String) -> Double {
        let renset = tekst.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        return Double(renset) ?? 0
    }
}
