import SwiftUI
import SwiftData

struct KjoreloggView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Kjoretur.dato, order: .reverse) private var turer: [Kjoretur]

    @State private var visNy = false

    private let aar = Date.now.aar
    private var satser: Skattesatser { .gjeldende(for: aar) }
    private var kmIAar: Double { turer.filter { $0.dato.aar == aar }.reduce(0) { $0 + $1.km } }

    var body: some View {
        List {
            Section {
                RadVerdi("Kjørt i \(String(aar))", "\(Int(kmIAar)) km")
                RadVerdi("Fradrag (\(satser.kmSatsPrivatBil.formatted(.number.precision(.fractionLength(2)))) kr/km)",
                         (kmIAar * satser.kmSatsPrivatBil).kr, uthevet: true)
            } footer: {
                Text("Gjelder når du bruker egen bil til oppdrag for foretaket, f.eks. møte med en kunde. Kjøring mellom hjem og fast jobb i politiet teller ikke. Sjekk gjeldende sats hos Skatteetaten. Kjører du over 6 000 km i året for foretaket, gjelder andre regler.")
            }

            Section("Turer") {
                ForEach(turer) { tur in
                    NavigationLink {
                        KjoreturSkjemaView(tur: tur)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tur.formal.isEmpty ? "\(tur.fra) – \(tur.til)" : tur.formal)
                                Text(tur.dato.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(tur.km.formatted(.number.precision(.fractionLength(0...1)))) km")
                                .monospacedDigit()
                        }
                    }
                }
                .onDelete { indekser in
                    for i in indekser { context.delete(turer[i]) }
                }
            }
        }
        .navigationTitle("Kjørelogg")
        .toolbar {
            Button {
                visNy = true
            } label: {
                Label("Ny tur", systemImage: "plus")
            }
        }
        .sheet(isPresented: $visNy) {
            NavigationStack {
                KjoreturSkjemaView(tur: nil)
            }
        }
    }
}

struct KjoreturSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var tur: Kjoretur
    private let erNy: Bool

    init(tur: Kjoretur?) {
        _tur = State(initialValue: tur ?? Kjoretur())
        erNy = tur == nil
    }

    var body: some View {
        Form {
            DatePicker("Dato", selection: $tur.dato, displayedComponents: .date)
            TextField("Fra", text: $tur.fra)
            TextField("Til", text: $tur.til)
            TextField("Formål (f.eks. «Møte med kunde om nettside»)", text: $tur.formal)
            HStack {
                Text("Kilometer tur/retur")
                Spacer()
                TextField("0", value: $tur.km, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }
        }
        .tastaturFerdigKnapp()
        .navigationTitle(erNy ? "Ny tur" : "Tur")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if erNy {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        context.insert(tur)
                        dismiss()
                    }
                    .disabled(tur.km <= 0)
                }
            }
        }
    }
}
