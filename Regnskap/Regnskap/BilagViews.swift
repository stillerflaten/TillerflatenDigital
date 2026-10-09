import SwiftUI
import SwiftData

struct BilagListeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bilag.dato, order: .reverse) private var bilag: [Bilag]

    @State private var sok = ""
    @State private var visNytt = false
    @State private var bareUbetalte = false

    private func erUbetalt(_ b: Bilag) -> Bool { b.erRegning && !b.erBetalt }

    /// Eldre år ligger i Arkiv. Ubetalte regninger vises alltid, og søk leter i alle år.
    private var filtrert: [Bilag] {
        bilag.filter { b in
            (!sok.isEmpty || Arkiv.erAktivt(b.dato.aar) || erUbetalt(b))
            && (!bareUbetalte || erUbetalt(b))
            && (sok.isEmpty
                || b.tittel.localizedCaseInsensitiveContains(sok)
                || b.notat.localizedCaseInsensitiveContains(sok)
                || b.kategori.navn.localizedCaseInsensitiveContains(sok))
        }
    }

    private var iArkivet: Int {
        bilag.filter { !Arkiv.erAktivt($0.dato.aar) && !erUbetalt($0) }.count
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
                BilagMaanedSeksjoner(bilag: filtrert)
                if sok.isEmpty && iArkivet > 0 {
                    ArkivLenke(antall: iArkivet, hva: "bilag")
                }
            }
            .temaBakgrunn()
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
            if let data = bilag.sorterteVedlegg.first?.data, let bilde = UIImage(data: data) {
                Image(uiImage: bilde)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .bottomTrailing) {
                        let antall = bilag.vedlegg?.count ?? 0
                        if antall > 1 {
                            Text("\(antall)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .background(Color.black.opacity(0.6), in: Capsule())
                                .padding(2)
                        }
                    }
            } else {
                Image(systemName: bilag.kategori.ikon)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.temaAksentMyk, in: RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(bilag.tittel.isEmpty ? bilag.kategori.navn : bilag.tittel)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(bilag.dato.formatted(date: .abbreviated, time: .omitted))
                    if bilag.erRegning && !bilag.erBetalt {
                        Text("· Ubetalt").foregroundStyle(.orange)
                    }
                    if (bilag.vedlegg ?? []).isEmpty {
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
    @State private var kalenderMelding: String?
    private let erNytt: Bool

    private func leggForfallIKalender() async {
        guard await Kalender.beOmTilgang() else {
            kalenderMelding = Kalender.Feil.ingenTilgang.errorDescription
            return
        }
        do {
            try Kalender.leggInn(regning: bilag)
            kalenderMelding = "Forfallet er lagt i kalenderen «\(Kalender.navn)», med varsel dagen før."
        } catch {
            kalenderMelding = "Kunne ikke legge inn i kalenderen: \(error.localizedDescription)"
        }
    }

    init(bilag: Bilag?) {
        _bilag = State(initialValue: bilag ?? Bilag())
        erNytt = bilag == nil
    }

    var body: some View {
        Form {
            Section("Kvittering") {
                VedleggVelger(bilag: bilag)
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
                    if !bilag.erBetalt && bilag.forfallsdato != nil {
                        Button {
                            Task { await leggForfallIKalender() }
                        } label: {
                            Label("Legg forfallet i kalenderen", systemImage: "calendar.badge.plus")
                        }
                    }
                }
            } footer: {
                if bilag.erRegning && !bilag.erBetalt {
                    Text("Du får et varsel dagen før forfall. Legger du det i kalenderen, fjernes det derfra når du markerer regningen som betalt.")
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
        .alert("Kalender", isPresented: Binding(get: { kalenderMelding != nil }, set: { if !$0 { kalenderMelding = nil } })) {
            Button("OK") { kalenderMelding = nil }
        } message: {
            Text(kalenderMelding ?? "")
        }
        .temaBakgrunn()
        .navigationTitle(erNytt ? "Nytt bilag" : "Bilag")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: bilag.erBetalt) { _, betalt in
            if betalt { Kalender.fjern(regning: bilag) }
        }
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
                        for v in bilag.vedlegg ?? [] { context.insert(v) }
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
