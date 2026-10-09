import SwiftUI
import SwiftData

struct BilagListeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bilag.dato, order: .reverse) private var bilag: [Bilag]

    @State private var sok = ""
    @State private var visNytt = false
    @State private var bareUbetalte = false

    private var filtrert: [Bilag] {
        bilag.filter { b in
            (!bareUbetalte || (b.erRegning && !b.erBetalt))
            && (sok.isEmpty
                || b.tittel.localizedCaseInsensitiveContains(sok)
                || b.notat.localizedCaseInsensitiveContains(sok)
                || b.kategori.navn.localizedCaseInsensitiveContains(sok))
        }
    }

    /// Bilagene gruppert per måned, nyeste først.
    private var maaneder: [(tittel: String, bilag: [Bilag])] {
        let cal = Frister.kalender
        let grupper = Dictionary(grouping: filtrert) { cal.dateInterval(of: .month, for: $0.dato)?.start ?? $0.dato }
        return grupper.keys.sorted(by: >).map { start in
            (tittel: start.formatted(.dateTime.month(.wide).year()).capitalized, bilag: grupper[start] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if bilag.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen bilag ennå", systemImage: "doc.text.viewfinder")
                    } description: {
                        Text("Ta bilde av kvitteringer og regninger med en gang du kjøper noe til foretaket. Du må ta vare på dem i fem år.")
                    } actions: {
                        Button("Legg inn første bilag") { visNytt = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(maaneder, id: \.tittel) { maaned in
                    Section {
                        ForEach(maaned.bilag) { b in
                            NavigationLink {
                                BilagSkjemaView(bilag: b)
                            } label: {
                                BilagRad(bilag: b)
                            }
                        }
                        .onDelete { indekser in
                            for i in indekser {
                                let b = maaned.bilag[i]
                                Varsler.fjernRegning(b)
                                context.delete(b)
                            }
                        }
                    } header: {
                        HStack {
                            Text(maaned.tittel)
                            Spacer()
                            Text(maaned.bilag.reduce(0) { $0 + $1.belop }.kr)
                        }
                    }
                }
            }
            .navigationTitle("Bilag")
            .searchable(text: $sok, prompt: "Søk i bilag")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $bareUbetalte) {
                        Label("Bare ubetalte", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .toggleStyle(.button)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        visNytt = true
                    } label: {
                        Label("Nytt bilag", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $visNytt) {
                NavigationStack {
                    BilagSkjemaView(bilag: nil)
                }
            }
        }
    }
}

struct BilagRad: View {
    let bilag: Bilag

    var body: some View {
        HStack(spacing: 12) {
            if let data = bilag.bilde, let bilde = UIImage(data: data) {
                Image(uiImage: bilde)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: bilag.kategori.ikon)
                    .frame(width: 40, height: 40)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(bilag.tittel.isEmpty ? bilag.kategori.navn : bilag.tittel)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(bilag.dato.formatted(date: .abbreviated, time: .omitted))
                    if bilag.erRegning && !bilag.erBetalt {
                        Text("· Ubetalt").foregroundStyle(.orange)
                    }
                    if bilag.bilde == nil {
                        Text("· Mangler bilde").foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(bilag.belop.kr)
                .monospacedDigit()
        }
    }
}

struct BilagSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false

    // @State holder på det samme objektet selv om skjermen tegnes på nytt,
    // så et nytt bilag ikke mistes mens du fyller det ut.
    @State private var bilag: Bilag
    private let erNytt: Bool

    init(bilag: Bilag?) {
        _bilag = State(initialValue: bilag ?? Bilag())
        erNytt = bilag == nil
    }

    var body: some View {
        Form {
            Section("Kvittering") {
                BildeVelger(bildeData: $bilag.bilde)
            }

            Section {
                TextField("Hva er kjøpt (f.eks. «Apple Developer Program»)", text: $bilag.tittel)
                DatePicker("Dato", selection: $bilag.dato, displayedComponents: .date)
                BelopFelt("Beløp inkl. mva", belop: $bilag.belop)
                if mvaRegistrert {
                    BelopFelt("Herav mva", belop: $bilag.mva)
                    Button("Regn ut 25 % mva") {
                        bilag.mva = (bilag.belop * 0.2).rounded(toPlaces: 2)
                    }
                    .font(.footnote)
                }
            }

            Section {
                Picker("Kategori", selection: $bilag.kategori) {
                    ForEach(Utgiftskategori.allCases) { k in
                        Label(k.navn, systemImage: k.ikon).tag(k)
                    }
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Brukes i foretaket")
                        Spacer()
                        Text("\(Int(bilag.naeringsandel)) %")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $bilag.naeringsandel, in: 0...100, step: 5)
                }
            } footer: {
                if let tekst = bilag.kategori.hjelpetekst {
                    Text(tekst)
                } else if bilag.kategori == .utstyr && bilag.belop >= Skattesatser.aar2026.direkteFradragGrense {
                    Text("Over 30 000 kr? Da må det avskrives. Velg «Utstyr over 30 000 kr».")
                }
            }

            Section {
                Toggle("Dette er en regning som skal betales", isOn: $bilag.erRegning)
                if bilag.erRegning {
                    DatePicker("Forfallsdato", selection: Binding(
                        get: { bilag.forfallsdato ?? .now },
                        set: { bilag.forfallsdato = $0 }
                    ), displayedComponents: .date)
                    Toggle("Betalt", isOn: $bilag.erBetalt)
                }
            } footer: {
                if bilag.erRegning && !bilag.erBetalt {
                    Text("Du får et varsel dagen før forfall.")
                }
            }

            Section("Notat") {
                TextField("Hvorfor kjøpte du dette? (hjelper deg ved skattemeldingen)", text: $bilag.notat, axis: .vertical)
                    .lineLimit(2...6)
            }

            if bilag.belop > 0 {
                Section {
                    RadVerdi("Fradrag", bilag.fradrag(mvaRegistrert: mvaRegistrert).kr, uthevet: true)
                } footer: {
                    Text(bilag.kategori == .driftsmiddel
                         ? "Avskrives over flere år, se Kalkulatorer → Avskrivning."
                         : "Trekkes fra overskuddet før skatt. Det sparer deg for omtrent en tredjedel av beløpet i skatt.")
                }
            }
        }
        .tastaturFerdigKnapp()
        .navigationTitle(erNytt ? "Nytt bilag" : "Bilag")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: bilag.erRegning) { _, erRegning in
            if erRegning && bilag.forfallsdato == nil {
                bilag.forfallsdato = Calendar.current.date(byAdding: .day, value: 14, to: .now)
                bilag.erBetalt = false
            }
        }
        .onDisappear {
            if !erNytt { Varsler.planleggRegning(bilag) }
        }
        .toolbar {
            if erNytt {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        context.insert(bilag)
                        Varsler.planleggRegning(bilag)
                        dismiss()
                    }
                    .disabled(bilag.belop <= 0)
                }
            }
        }
    }
}

extension Double {
    func rounded(toPlaces plasser: Int) -> Double {
        let faktor = pow(10, Double(plasser))
        return (self * faktor).rounded() / faktor
    }
}
