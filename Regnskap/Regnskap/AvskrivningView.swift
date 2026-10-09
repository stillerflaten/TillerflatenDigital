import SwiftUI
import SwiftData

struct AvskrivningView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Driftsmiddel.kjopsdato, order: .reverse) private var driftsmidler: [Driftsmiddel]

    @State private var pris: Double = 0
    @State private var gruppe: Saldogruppe = .a
    @State private var andel: Double = 100
    @State private var levetid3Aar = true
    @State private var visNytt = false

    private let aar = Date.now.aar
    private var satser: Skattesatser { .gjeldende(for: aar) }

    var body: some View {
        Form {
            Section {
                BelopFelt("Pris", belop: $pris)
                Picker("Type utstyr", selection: $gruppe) {
                    ForEach(Saldogruppe.allCases) { Text($0.navn).tag($0) }
                }
                Toggle("Varer minst tre år", isOn: $levetid3Aar)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Brukes i foretaket")
                        Spacer()
                        Text("\(Int(andel)) %").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $andel, in: 0...100, step: 5)
                }
            } header: {
                Text("Regn ut fradrag")
            } footer: {
                Text("\(gruppe.eksempler). Prisen skal være inkl. mva hvis du ikke er mva-registrert.")
            }

            if pris > 0 {
                resultat
            }

            Section {
                if driftsmidler.isEmpty {
                    Text("Utstyr du legger inn her, tas med i oversikten og skatteberegningen hvert år.")
                        .foregroundStyle(.secondary)
                }
                ForEach(driftsmidler) { d in
                    NavigationLink {
                        DriftsmiddelSkjemaView(driftsmiddel: d)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(d.navn.isEmpty ? "Utstyr" : d.navn)
                                Text("\(String(d.kjopsaar)) · \(beskrivelse(d))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(d.kostpris.kr).monospacedDigit()
                        }
                    }
                }
                .onDelete { indekser in
                    for i in indekser { context.delete(driftsmidler[i]) }
                }
                Button {
                    visNytt = true
                } label: {
                    Label("Legg til utstyr", systemImage: "plus")
                }
            } header: {
                Text("Mitt utstyr")
            }

            Section {
                Text("Utstyr under 30 000 kr, eller som varer kortere enn tre år, trekker du fra i sin helhet samme år som du kjøper det.")
                Text("Dyrere utstyr legges i en «saldogruppe» og trekkes fra med en fast prosent av restverdien hvert år: 30 % for datautstyr (gruppe a), 20 % for inventar, maskiner og personbil (gruppe d). Det spiller ingen rolle hvilken måned du kjøpte det.")
                Text("Når restverdien i en gruppe kommer under 30 000 kr, kan du trekke fra hele resten på én gang.")
                Text("Bruker du utstyret også privat, kan du bare trekke fra den delen som gjelder foretaket.")
                Link("Les mer hos Skatteetaten", destination: Kilder.driftsmidler)
            } header: {
                Text("Slik fungerer det")
            }
        }
        .tastaturFerdigKnapp()
        .navigationTitle("Avskrivning")
        .sheet(isPresented: $visNytt) {
            NavigationStack {
                DriftsmiddelSkjemaView(driftsmiddel: nil, forslag: (pris: pris, gruppe: gruppe, andel: andel, levetid: levetid3Aar))
            }
        }
    }

    @ViewBuilder
    private var resultat: some View {
        switch Avskrivning.metode(kostpris: pris, naeringsandel: andel / 100, levetidMinst3Aar: levetid3Aar,
                                  gruppe: gruppe, satser: satser) {
        case .direkteFradrag(let belop):
            Section {
                RadVerdi("Fradrag i \(String(aar))", belop.kr, uthevet: true)
                RadVerdi("Du sparer ca. i skatt", (belop * marginalsats).kr)
            } header: {
                Text("Direkte fradrag")
            } footer: {
                Text(pris < satser.direkteFradragGrense
                     ? "Under 30 000 kr: hele beløpet trekkes fra i år. Registrer kvitteringen som bilag med kategori «Utstyr under 30 000 kr»."
                     : "Varer kortere enn tre år: hele beløpet trekkes fra i år.")
            }
        case .saldo(let gruppe, let grunnlag):
            let plan = Avskrivning.plan(forEttKjop: grunnlag, aar: aar, gruppe: gruppe, satser: satser)
            Section {
                ForEach(plan.prefix(8)) { rad in
                    HStack {
                        Text(String(rad.aar))
                        if rad.lavSaldoFradrag {
                            Text("rest").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(rad.avskrivning.kr).monospacedDigit()
                    }
                }
                if plan.count > 8 {
                    Text("… og \(plan.count - 8) år til")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Avskrives over \(plan.count) år")
            } footer: {
                Text("Forutsetter at dette er det eneste utstyret i gruppen. Legg det inn under «Mitt utstyr», så regner appen med alt sammen.")
            }
        }
    }

    @AppStorage(Innstilling.lonn) private var lonn: Double = 0
    private var marginalsats: Double { EnkSkatt(lonn: lonn, overskudd: 0, satser: satser).marginalsats }

    private func beskrivelse(_ d: Driftsmiddel) -> String {
        switch d.metode(satser: satser) {
        case .direkteFradrag: "direkte fradrag"
        case .saldo(let g, _): "saldogruppe \(g.rawValue)"
        }
    }
}

struct DriftsmiddelSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var driftsmiddel: Driftsmiddel
    private let erNytt: Bool

    init(driftsmiddel: Driftsmiddel?, forslag: (pris: Double, gruppe: Saldogruppe, andel: Double, levetid: Bool)? = nil) {
        let d = driftsmiddel ?? Driftsmiddel()
        if driftsmiddel == nil, let forslag {
            d.kostpris = forslag.pris
            d.gruppe = forslag.gruppe
            d.naeringsandel = forslag.andel
            d.levetidMinst3Aar = forslag.levetid
        }
        _driftsmiddel = State(initialValue: d)
        erNytt = driftsmiddel == nil
    }

    var body: some View {
        let satser = Skattesatser.gjeldende(for: driftsmiddel.kjopsaar)
        Form {
            Section {
                TextField("Navn (f.eks. «MacBook Pro 14»)", text: $driftsmiddel.navn)
                DatePicker("Kjøpt", selection: $driftsmiddel.kjopsdato, displayedComponents: .date)
                BelopFelt("Pris", belop: $driftsmiddel.kostpris)
                Picker("Type", selection: $driftsmiddel.gruppe) {
                    ForEach(Saldogruppe.allCases) { Text($0.navn).tag($0) }
                }
                Toggle("Varer minst tre år", isOn: $driftsmiddel.levetidMinst3Aar)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Brukes i foretaket")
                        Spacer()
                        Text("\(Int(driftsmiddel.naeringsandel)) %").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $driftsmiddel.naeringsandel, in: 0...100, step: 5)
                }
            } footer: {
                if case .direkteFradrag = driftsmiddel.metode(satser: satser), driftsmiddel.kostpris > 0 {
                    Text("Dette trekkes fra i sin helhet i \(String(driftsmiddel.kjopsaar)). Ikke registrer det i tillegg som bilag med kategori «Utstyr under 30 000 kr», da blir fradraget dobbelt.")
                }
            }
            Section("Notat") {
                TextField("Serienummer, hvor det er kjøpt osv.", text: $driftsmiddel.notat, axis: .vertical)
            }
        }
        .tastaturFerdigKnapp()
        .navigationTitle(erNytt ? "Nytt utstyr" : "Utstyr")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if erNytt {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        context.insert(driftsmiddel)
                        dismiss()
                    }
                    .disabled(driftsmiddel.kostpris <= 0)
                }
            }
        }
    }
}
