import SwiftUI
import SwiftData

enum Trekkintervall: String, CaseIterable, Identifiable {
    case maanedlig, kvartalsvis, aarlig

    var id: String { rawValue }

    var navn: String {
        switch self {
        case .maanedlig: "Hver måned"
        case .kvartalsvis: "Hvert kvartal"
        case .aarlig: "Hvert år"
        }
    }

    var maaneder: Int {
        switch self {
        case .maanedlig: 1
        case .kvartalsvis: 3
        case .aarlig: 12
        }
    }
}

/// Et abonnement eller en annen utgift som trekkes jevnlig, f.eks. Apple Developer Program.
@Model
final class FastUtgift {
    var uuid: UUID = UUID()
    var navn: String = ""
    /// Omtrentlig beløp i kroner. Det faktiske beløpet står på kvitteringen.
    var belop: Double = 0
    var kategoriRaw: String = Utgiftskategori.programvare.rawValue
    var intervallRaw: String = Trekkintervall.maanedlig.rawValue
    /// Neste gang utgiften trekkes.
    var nesteTrekk: Date = Date.now
    var naeringsandel: Double = 100
    var aktiv: Bool = true
    var notat: String = ""
    /// Kjøpt fra utlandet uten norsk mva, se `Bilag.fraUtlandet`.
    var fraUtlandet: Bool = false

    init(navn: String = "") {
        self.navn = navn
    }

    var kategori: Utgiftskategori {
        get { Utgiftskategori(rawValue: kategoriRaw) ?? .programvare }
        set { kategoriRaw = newValue.rawValue }
    }

    var intervall: Trekkintervall {
        get { Trekkintervall(rawValue: intervallRaw) ?? .maanedlig }
        set { intervallRaw = newValue.rawValue }
    }

    /// Trekket har skjedd, men kvitteringen er ikke lagt inn.
    var venterPaaKvittering: Bool {
        aktiv && Frister.kalender.startOfDay(for: nesteTrekk) <= Frister.kalender.startOfDay(for: .now)
    }

    /// Hva det koster i året, omtrent.
    var perAar: Double { belop * Double(12 / intervall.maaneder) }

    /// Flytter neste trekk ett intervall fram, etter at kvitteringen er lagt inn eller hoppet over.
    func gaaTilNeste() {
        nesteTrekk = FasteUtgifter.neste(etter: nesteTrekk, intervall: intervall)
        Varsler.planleggFastUtgift(self)
    }

    /// Et nytt bilag fylt ut med det vi vet om utgiften.
    func forslagTilBilag() -> Bilag {
        let b = Bilag(dato: nesteTrekk, tittel: navn, belop: belop, kategori: kategori)
        b.naeringsandel = naeringsandel
        b.notat = notat
        b.fraUtlandet = fraUtlandet
        return b
    }
}

enum FasteUtgifter {
    static func neste(etter dato: Date, intervall: Trekkintervall) -> Date {
        Frister.kalender.date(byAdding: .month, value: intervall.maaneder, to: dato) ?? dato
    }
}

// MARK: Visninger

struct FasteUtgifterView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FastUtgift.nesteTrekk) private var utgifter: [FastUtgift]

    @State private var visNy = false

    private var venter: [FastUtgift] { utgifter.filter(\.venterPaaKvittering) }
    private var kommende: [FastUtgift] { utgifter.filter { $0.aktiv && !$0.venterPaaKvittering } }
    private var stoppet: [FastUtgift] { utgifter.filter { !$0.aktiv } }

    var body: some View {
        List {
            if utgifter.isEmpty {
                ContentUnavailableView {
                    Label("Ingen faste utgifter", systemImage: "repeat")
                } description: {
                    Text("Legg inn abonnementer som Apple Developer Program, domene, webhotell og Claude. Appen minner deg på å legge inn kvitteringen når de trekkes.")
                } actions: {
                    Button("Legg inn den første") { visNy = true }
                        .buttonStyle(.borderedProminent)
                }
            }

            if !venter.isEmpty {
                Section {
                    ForEach(venter) { u in
                        VenterPaaKvitteringRad(utgift: u)
                    }
                } header: {
                    Text("Legg inn kvitteringen")
                } footer: {
                    Text("Disse er trukket. Legg inn kvitteringen, eller hopp over hvis den ikke ble trukket denne gangen.")
                }
            }

            if !kommende.isEmpty {
                Section {
                    ForEach(kommende) { u in
                        NavigationLink {
                            FastUtgiftSkjemaView(utgift: u)
                        } label: {
                            FastUtgiftRad(utgift: u)
                        }
                    }
                } header: {
                    HStack {
                        Text("Kommende")
                        Spacer()
                        Text("\(utgifter.filter(\.aktiv).reduce(0) { $0 + $1.perAar }.kr) i året")
                    }
                }
            }

            if !stoppet.isEmpty {
                Section("Avsluttet") {
                    ForEach(stoppet) { u in
                        NavigationLink {
                            FastUtgiftSkjemaView(utgift: u)
                        } label: {
                            FastUtgiftRad(utgift: u)
                        }
                    }
                }
            }
        }
        .temaBakgrunn()
        .navigationTitle("Faste utgifter")
        .toolbar {
            Button {
                visNy = true
            } label: {
                Label("Ny fast utgift", systemImage: "plus")
            }
        }
        .sheet(isPresented: $visNy) {
            NavigationStack {
                FastUtgiftSkjemaView(utgift: nil)
            }
        }
    }
}

struct FastUtgiftRad: View {
    let utgift: FastUtgift

    var body: some View {
        HStack {
            Image(systemName: utgift.kategori.ikon)
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.accentColor)
                .background(Color.temaAksentMyk, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(utgift.navn)
                Text(utgift.aktiv
                     ? "\(utgift.intervall.navn) · neste \(utgift.nesteTrekk.formatted(date: .abbreviated, time: .omitted))"
                     : "Avsluttet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(utgift.belop.kr)
                .monospacedDigit()
        }
    }
}

/// Rad for en utgift som er trukket: legg inn kvitteringen eller hopp over.
struct VenterPaaKvitteringRad: View {
    let utgift: FastUtgift
    @State private var visBilag = false
    @State private var visEndre = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FastUtgiftRad(utgift: utgift)
            HStack {
                Button {
                    visBilag = true
                } label: {
                    Label("Legg inn kvittering", systemImage: "doc.text.viewfinder")
                }
                .buttonStyle(.borderedProminent)
                Button("Hopp over") {
                    utgift.gaaTilNeste()
                }
                .buttonStyle(.bordered)
                Button("Endre") {
                    visEndre = true
                }
                .buttonStyle(.bordered)
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $visBilag) {
            NavigationStack {
                BilagSkjemaView(forslag: utgift.forslagTilBilag()) {
                    utgift.gaaTilNeste()
                }
            }
        }
        .sheet(isPresented: $visEndre) {
            NavigationStack {
                FastUtgiftSkjemaView(utgift: utgift)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Ferdig") { visEndre = false }
                        }
                    }
            }
        }
    }
}

struct FastUtgiftSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var utgift: FastUtgift
    @State private var bekreftSlett = false
    @State private var slettet = false
    private let erNy: Bool

    init(utgift: FastUtgift?) {
        _utgift = State(initialValue: utgift ?? FastUtgift())
        erNy = utgift == nil
    }

    var body: some View {
        Form {
            Section {
                TextField("Navn (f.eks. «Apple Developer Program»)", text: $utgift.navn)
                BelopFelt("Beløp, omtrent", belop: $utgift.belop)
                Picker("Trekkes", selection: $utgift.intervall) {
                    ForEach(Trekkintervall.allCases) { Text($0.navn).tag($0) }
                }
                DatePicker("Neste trekk", selection: $utgift.nesteTrekk, displayedComponents: .date)
            } footer: {
                Text("Betaler du i dollar, skriv omtrent hva det blir i kroner. Det riktige beløpet tar du fra kvitteringen.")
            }

            Section {
                Picker("Kategori", selection: $utgift.kategori) {
                    ForEach(Utgiftskategori.allCases) { k in
                        Label(k.navn, systemImage: k.ikon).tag(k)
                    }
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Brukes i foretaket")
                        Spacer()
                        Text("\(Int(utgift.naeringsandel)) %")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $utgift.naeringsandel, in: 0...100, step: 5)
                }
                Toggle("Kjøpt fra utlandet uten norsk mva", isOn: $utgift.fraUtlandet)
                TextField("Notat (f.eks. hvilket kort det trekkes fra)", text: $utgift.notat, axis: .vertical)
            }

            if !erNy {
                Section {
                    Toggle("Aktiv", isOn: $utgift.aktiv)
                } footer: {
                    Text("Slå av når du sier opp abonnementet. Da får du ikke flere påminnelser.")
                }

                Section {
                    Button("Slett", role: .destructive) { bekreftSlett = true }
                        .confirmationDialog("Slette \(utgift.navn)?", isPresented: $bekreftSlett, titleVisibility: .visible) {
                            Button("Slett", role: .destructive) {
                                let u = utgift
                                slettet = true
                                Varsler.fjernFastUtgift(u)
                                dismiss()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(500))
                                    context.delete(u)
                                    try? context.save()
                                }
                            }
                        } message: {
                            Text("Kvitteringer du allerede har lagt inn, blir liggende.")
                        }
                }
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle(erNy ? "Ny fast utgift" : utgift.navn)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if !erNy && !slettet { Varsler.planleggFastUtgift(utgift) }
        }
        .toolbar {
            if erNy {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        context.insert(utgift)
                        let u = utgift
                        Task {
                            _ = await Varsler.beOmTillatelse()
                            Varsler.planleggFastUtgift(u)
                        }
                        dismiss()
                    }
                    .disabled(utgift.navn.trimmet.isEmpty)
                }
            }
        }
    }
}
