import SwiftUI
import SwiftData

struct InntekterView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Inntekt.dato, order: .reverse) private var inntekter: [Inntekt]

    @Query private var fakturaer: [Faktura]
    @State private var visNy = false

    private var ubetalteFakturaer: [Faktura] { fakturaer.filter { $0.status == .sendt } }

    private var perAar: [(aar: Int, inntekter: [Inntekt])] {
        Dictionary(grouping: inntekter.filter { Arkiv.erAktivt($0.dato.aar) }, by: \.dato.aar)
            .sorted { $0.key > $1.key }
            .map { (aar: $0.key, inntekter: $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FakturaListeView()
                    } label: {
                        HStack {
                            Label("Fakturaer", systemImage: "doc.richtext")
                            Spacer()
                            if !ubetalteFakturaer.isEmpty {
                                Text("\(ubetalteFakturaer.count) ubetalt")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ubetalteFakturaer.contains(where: \.erForfalt) ? Color.red : Color.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Lag faktura til kunder. Når kunden har betalt, havner beløpet her av seg selv.")
                }

                if inntekter.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen inntekter ennå", systemImage: "banknote")
                    } description: {
                        Text("Legg inn hver utbetaling fra Apple når den kommer på konto. Beløpet finner du i App Store Connect under Payments and Financial Reports, eller på kontoutskriften.")
                    } actions: {
                        Button("Legg inn utbetaling") { visNy = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(perAar, id: \.aar) { gruppe in
                    Section {
                        ForEach(gruppe.inntekter) { inntekt in
                            NavigationLink {
                                InntektSkjemaView(inntekt: inntekt)
                            } label: {
                                InntektRad(inntekt: inntekt)
                            }
                        }
                        .onDelete { indekser in
                            for i in indekser { context.delete(gruppe.inntekter[i]) }
                        }
                    } header: {
                        HStack {
                            Text(String(gruppe.aar))
                            Spacer()
                            Text(gruppe.inntekter.reduce(0) { $0 + $1.belop }.kr)
                        }
                    }
                }
                let iArkivet = inntekter.filter { !Arkiv.erAktivt($0.dato.aar) }.count
                if iArkivet > 0 {
                    ArkivLenke(antall: iArkivet, hva: "inntekter")
                }
            }
            .temaBakgrunn()
            .navigationTitle("Inntekter")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        visNy = true
                    } label: {
                        Label("Ny inntekt", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $visNy) {
                NavigationStack {
                    InntektSkjemaView(inntekt: nil)
                }
            }
        }
    }
}

struct InntektSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Innstilling.lonn) private var lonn: Double = 0

    @State private var inntekt: Inntekt
    private let erNy: Bool

    private let kilder = ["App Store", "Nettside-oppdrag", "Annet"]

    init(inntekt: Inntekt?) {
        _inntekt = State(initialValue: inntekt ?? Inntekt())
        erNy = inntekt == nil
    }

    var body: some View {
        Form {
            Section {
                Picker("Kilde", selection: $inntekt.kilde) {
                    ForEach(kilder, id: \.self) { Text($0).tag($0) }
                    if !kilder.contains(inntekt.kilde) {
                        Text(inntekt.kilde).tag(inntekt.kilde)
                    }
                }
                DatePicker("Dato på konto", selection: $inntekt.dato, displayedComponents: .date)
                BelopFelt("Beløp utbetalt", belop: $inntekt.belop)
            } footer: {
                Text("Fra App Store: bruk beløpet som faktisk kom inn på konto i kroner. Apple har da allerede trukket sin provisjon (15 % i Small Business Program) og betalt mva til land som krever det.")
            }

            Section("Dokumentasjon") {
                BildeVelger(bildeData: $inntekt.bilde)
                TextField("Notat (f.eks. «Payment for August»)", text: $inntekt.notat, axis: .vertical)
            }

            if inntekt.belop > 0 {
                let skatt = EnkSkatt(lonn: lonn, overskudd: 0, satser: .gjeldende(for: inntekt.dato.aar))
                Section {
                    RadVerdi("Sett av til skatt (ca.)", (inntekt.belop * skatt.marginalsats).kr, uthevet: true)
                } footer: {
                    Text("Grovt anslag: \(skatt.marginalsats.prosent) av utbetalingen, ut fra lønnen din. Fradrag for utgifter gjør den faktiske skatten lavere. Se Kalkulatorer → Skatt for hele året.")
                }
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle(erNy ? "Ny inntekt" : "Inntekt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if erNy {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        context.insert(inntekt)
                        dismiss()
                    }
                    .disabled(inntekt.belop <= 0)
                }
            }
        }
    }
}
