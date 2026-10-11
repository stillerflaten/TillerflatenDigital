import SwiftUI
import SwiftData

// MARK: Modeller

/// Et oppdrag for en kunde, på timepris eller fastpris. Timene føres for hånd.
@Model
final class Prosjekt {
    var uuid: UUID = UUID()
    var navn: String = ""
    var kundeUUID: UUID? = nil
    /// Kopi av kundens navn, så prosjektet har et navn å vise selv om kunden slettes.
    var kundeNavn: String = ""
    var erFastpris: Bool = false
    /// Pris per time uten mva. Brukes på timepris.
    var timepris: Double = 0
    /// Avtalt pris for hele oppdraget uten mva. Brukes på fastpris.
    var fastpris: Double = 0
    var ferdig: Bool = false
    var opprettet: Date = Date.now
    var notat: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Timeforing.prosjekt) var foringer: [Timeforing]? = []

    init(navn: String = "") {
        self.navn = navn
    }

    var sorterteForinger: [Timeforing] {
        (foringer ?? []).sorted { $0.dato > $1.dato }
    }

    var sumTimer: Double { Timebank.sum(foringer ?? []) }
}

/// Timer brukt på et prosjekt én dag.
@Model
final class Timeforing {
    var uuid: UUID = UUID()
    var dato: Date = Date.now
    var timer: Double = 0
    var notat: String = ""
    /// Fakturaen timene er tatt med på. Slettes fakturautkastet, regnes timene som ufakturert igjen.
    var fakturaUUID: UUID? = nil
    var prosjekt: Prosjekt?

    init(dato: Date = .now, timer: Double = 0, notat: String = "") {
        self.dato = dato
        self.timer = timer
        self.notat = notat
    }
}

// MARK: Beregninger

enum Timebank {
    static func sum(_ foringer: [Timeforing]) -> Double {
        foringer.reduce(0) { $0 + $1.timer }
    }

    /// Timer som ikke er med på en faktura som finnes.
    static func ufakturerte(_ foringer: [Timeforing], fakturaer: Set<UUID>) -> [Timeforing] {
        foringer.filter { f in f.fakturaUUID.map { !fakturaer.contains($0) } ?? true }
    }

    /// Hva du har tjent per time. Nil når det ikke er ført timer.
    static func effektivTimepris(pris: Double, timer: Double) -> Double? {
        timer > 0 ? pris / timer : nil
    }

    /// Teksten på fakturalinjen for én dag.
    static func beskrivelse(for foring: Timeforing, prosjektnavn: String) -> String {
        let dato = foring.dato.formatted(.dateTime.day().month(.twoDigits).year().locale(Locale(identifier: "nb_NO")))
        let hva = foring.notat.trimmet.isEmpty ? prosjektnavn.trimmet : foring.notat.trimmet
        return hva.isEmpty ? dato : "\(dato): \(hva)"
    }

    /// Lager et fakturautkast med én linje per dag, og merker timene som fakturert.
    @MainActor
    static func lagFaktura(for prosjekt: Prosjekt, foringer: [Timeforing], kunde: Kunde?, context: ModelContext) -> Faktura {
        let f = Fakturering.nyttUtkast(context: context)
        if let kunde {
            Fakturering.kopier(kunde, til: f)
        } else {
            f.kundeNavn = prosjekt.kundeNavn
        }
        let sortert = foringer.sorted { $0.dato < $1.dato }
        f.leveringsdato = sortert.last?.dato ?? f.leveringsdato
        var linjer: [FakturaLinje] = []
        for (i, t) in sortert.enumerated() {
            let l = FakturaLinje(nr: i + 1, beskrivelse: beskrivelse(for: t, prosjektnavn: prosjekt.navn),
                                 antall: t.timer, enhetspris: prosjekt.timepris)
            context.insert(l)
            linjer.append(l)
            t.fakturaUUID = f.uuid
        }
        f.linjer = linjer
        try? context.save()
        return f
    }

    static func timer(_ verdi: Double) -> String {
        "\(Fakturering.antall(verdi)) t"
    }
}

// MARK: Prosjekter

struct ProsjektListeView: View {
    @Query(sort: \Prosjekt.opprettet, order: .reverse) private var prosjekter: [Prosjekt]
    @Query private var fakturaer: [Faktura]
    @Query private var alleForinger: [Timeforing]
    @State private var visNy = false

    private var aktive: [Prosjekt] { prosjekter.filter { !$0.ferdig } }
    private var ferdige: [Prosjekt] { prosjekter.filter(\.ferdig) }

    var body: some View {
        let fakturaIDer = Set(fakturaer.map(\.uuid))
        List {
            if prosjekter.isEmpty {
                ContentUnavailableView {
                    Label("Ingen prosjekter ennå", systemImage: "clock")
                } description: {
                    Text("Lag et prosjekt for hvert oppdrag og før timene du bruker. På timepris lager du faktura rett fra timene. På fastpris ser du hva du faktisk tjente i timen.")
                } actions: {
                    Button("Nytt prosjekt") { visNy = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Section {
                    RadVerdi("Denne måneden", Timebank.timer(Timebank.sum(alleForinger.filter {
                        Frister.kalender.isDate($0.dato, equalTo: .now, toGranularity: .month)
                    })))
                    RadVerdi("I år", Timebank.timer(Timebank.sum(alleForinger.filter { $0.dato.aar == Date.now.aar })))
                } header: {
                    Text("Timer på foretaket")
                }
            }

            if !aktive.isEmpty {
                Section("Pågår") {
                    ForEach(aktive) { p in
                        NavigationLink { ProsjektView(prosjekt: p) } label: { ProsjektRad(prosjekt: p, fakturaIDer: fakturaIDer) }
                    }
                }
            }
            if !ferdige.isEmpty {
                Section("Ferdige") {
                    ForEach(ferdige) { p in
                        NavigationLink { ProsjektView(prosjekt: p) } label: { ProsjektRad(prosjekt: p, fakturaIDer: fakturaIDer) }
                    }
                }
            }
        }
        .temaBakgrunn()
        .navigationTitle("Timer og prosjekter")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    visNy = true
                } label: {
                    Label("Nytt prosjekt", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $visNy) {
            NavigationStack {
                ProsjektSkjemaView(prosjekt: nil)
            }
        }
    }
}

private struct ProsjektRad: View {
    let prosjekt: Prosjekt
    let fakturaIDer: Set<UUID>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(prosjekt.navn).lineLimit(1)
                Text(undertekst)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Timebank.timer(prosjekt.sumTimer))
                .monospacedDigit()
        }
    }

    private var undertekst: String {
        var deler: [String] = []
        if !prosjekt.kundeNavn.isEmpty { deler.append(prosjekt.kundeNavn) }
        if prosjekt.erFastpris {
            if let t = Timebank.effektivTimepris(pris: prosjekt.fastpris, timer: prosjekt.sumTimer) {
                deler.append("\(t.kr) i timen")
            } else {
                deler.append("Fastpris")
            }
        } else {
            let ufakturert = Timebank.sum(Timebank.ufakturerte(prosjekt.foringer ?? [], fakturaer: fakturaIDer))
            deler.append(ufakturert > 0 ? "\(Timebank.timer(ufakturert)) ikke fakturert" : "Alt er fakturert")
        }
        return deler.joined(separator: " · ")
    }
}

/// Ett prosjekt: timene som er ført, og hva de er verdt.
struct ProsjektView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var fakturaer: [Faktura]
    @Query(sort: \Kunde.navn) private var kunder: [Kunde]

    @Bindable var prosjekt: Prosjekt

    @State private var visNyeTimer = false
    @State private var endre: Timeforing?
    @State private var nyFaktura: Faktura?

    var body: some View {
        let fakturaIDer = Set(fakturaer.map(\.uuid))
        let ufakturerte = Timebank.ufakturerte(prosjekt.foringer ?? [], fakturaer: fakturaIDer)
        let ufakturerteTimer = Timebank.sum(ufakturerte)

        Form {
            Section {
                RadVerdi("Timer totalt", Timebank.timer(prosjekt.sumTimer), uthevet: true)
                if prosjekt.erFastpris {
                    RadVerdi("Avtalt pris", prosjekt.fastpris.kr)
                    if let t = Timebank.effektivTimepris(pris: prosjekt.fastpris, timer: prosjekt.sumTimer) {
                        RadVerdi("Du tjener", "\(t.kr) i timen", uthevet: true)
                    }
                } else {
                    RadVerdi("Timepris", prosjekt.timepris.kr)
                    RadVerdi("Ikke fakturert", Timebank.timer(ufakturerteTimer))
                    if ufakturerteTimer > 0 {
                        RadVerdi("Verdi", Fakturering.rund(ufakturerteTimer * prosjekt.timepris).kr)
                    }
                }
            } header: {
                if !prosjekt.kundeNavn.isEmpty { Text(prosjekt.kundeNavn) }
            } footer: {
                if prosjekt.erFastpris {
                    Text("Avtalt pris delt på timene du har brukt. Beløpene er uten mva.")
                }
            }

            if !prosjekt.erFastpris && ufakturerteTimer > 0 {
                Section {
                    Button {
                        let kunde = kunder.first { $0.uuid == prosjekt.kundeUUID }
                        nyFaktura = Timebank.lagFaktura(for: prosjekt, foringer: ufakturerte, kunde: kunde, context: context)
                    } label: {
                        Label("Lag fakturautkast av \(Timebank.timer(ufakturerteTimer))", systemImage: "doc.richtext")
                    }
                    .disabled(prosjekt.timepris <= 0)
                } footer: {
                    Text(prosjekt.timepris <= 0
                         ? "Legg inn timepris under «Endre prosjektet» først."
                         : "Utkastet får én linje per dag. Du kan endre det før du sender. Sletter du utkastet, blir timene ufakturert igjen.")
                }
            }

            Section {
                Button {
                    visNyeTimer = true
                } label: {
                    Label("Før timer", systemImage: "plus.circle")
                }
                ForEach(prosjekt.sorterteForinger) { t in
                    Button {
                        endre = t
                    } label: {
                        TimeforingRad(foring: t, fakturert: !ufakturerte.contains { $0.uuid == t.uuid })
                    }
                    .tint(.primary)
                }
                .onDelete { indekser in
                    let liste = prosjekt.sorterteForinger
                    for i in indekser {
                        let t = liste[i]
                        prosjekt.foringer?.removeAll { $0 == t }
                        context.delete(t)
                    }
                    try? context.save()
                }
            } header: {
                Text("Timer")
            }

            if !prosjekt.notat.isEmpty {
                Section("Notater") {
                    Text(prosjekt.notat)
                }
            }

            Section {
                NavigationLink {
                    ProsjektSkjemaView(prosjekt: prosjekt, slettet: { dismiss() })
                } label: {
                    Label("Endre prosjektet", systemImage: "pencil")
                }
            }
        }
        .temaBakgrunn()
        .navigationTitle(prosjekt.navn)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $nyFaktura) { FakturaView(faktura: $0) }
        .sheet(isPresented: $visNyeTimer) {
            NavigationStack {
                TimeforingSkjemaView(prosjekt: prosjekt, foring: nil)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $endre) { t in
            NavigationStack {
                TimeforingSkjemaView(prosjekt: prosjekt, foring: t)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct TimeforingRad: View {
    let foring: Timeforing
    let fakturert: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(foring.dato.formatted(date: .abbreviated, time: .omitted))
                if !foring.notat.isEmpty {
                    Text(foring.notat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if fakturert && !(foring.prosjekt?.erFastpris ?? false) {
                Text("Fakturert")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Text(Timebank.timer(foring.timer))
                .monospacedDigit()
        }
    }
}

struct ProsjektSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Kunde.navn) private var kunder: [Kunde]

    @State private var prosjekt: Prosjekt
    @State private var visNyKunde = false
    @State private var bekreftSlett = false
    private let erNy: Bool
    /// Lukker prosjektsiden bak skjemaet når prosjektet slettes.
    private let slettet: (() -> Void)?

    init(prosjekt: Prosjekt?, slettet: (() -> Void)? = nil) {
        _prosjekt = State(initialValue: prosjekt ?? Prosjekt())
        erNy = prosjekt == nil
        self.slettet = slettet
    }

    var body: some View {
        Form {
            Section {
                TextField("Navn, f.eks. «Nettside for Kafé Fjord»", text: $prosjekt.navn)
                Picker("Kunde", selection: Binding(
                    get: { prosjekt.kundeUUID },
                    set: { id in
                        prosjekt.kundeUUID = id
                        prosjekt.kundeNavn = kunder.first { $0.uuid == id }?.navn ?? ""
                    })) {
                    Text("Ingen kunde").tag(UUID?.none)
                    if let id = prosjekt.kundeUUID, !kunder.contains(where: { $0.uuid == id }) {
                        Text(prosjekt.kundeNavn).tag(Optional(id))
                    }
                    ForEach(kunder) { k in
                        Text(k.navn).tag(Optional(k.uuid))
                    }
                }
                Button {
                    visNyKunde = true
                } label: {
                    Label("Ny kunde", systemImage: "person.badge.plus")
                }
            }

            Section {
                Picker("Pris", selection: $prosjekt.erFastpris) {
                    Text("Timepris").tag(false)
                    Text("Fastpris").tag(true)
                }
                .pickerStyle(.segmented)
                if prosjekt.erFastpris {
                    BelopFelt("Avtalt pris", belop: $prosjekt.fastpris)
                } else {
                    BelopFelt("Per time", belop: $prosjekt.timepris)
                }
            } footer: {
                Text(prosjekt.erFastpris
                     ? "Uten mva. Appen regner ut hva du tjener i timen ut fra timene du fører."
                     : "Uten mva. Mva legges på fakturaen hvis du er registrert.")
            }

            Section("Notater") {
                TextField("Hva dere har avtalt, frister osv.", text: $prosjekt.notat, axis: .vertical)
                    .lineLimit(2...8)
            }

            if !erNy {
                Section {
                    Toggle("Prosjektet er ferdig", isOn: $prosjekt.ferdig)
                } footer: {
                    Text("Ferdige prosjekter flyttes ned i listen. Timene blir liggende.")
                }
                Section {
                    Button("Slett prosjektet", role: .destructive) { bekreftSlett = true }
                        .confirmationDialog("Slette \(prosjekt.navn)?", isPresented: $bekreftSlett, titleVisibility: .visible) {
                            Button("Slett", role: .destructive) {
                                let p = prosjekt
                                if let slettet { slettet() } else { dismiss() }
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(500))
                                    context.delete(p)
                                    try? context.save()
                                }
                            }
                        } message: {
                            Text("Alle timene i prosjektet slettes. Fakturaer du har laget, blir ikke berørt.")
                        }
                }
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle(erNy ? "Nytt prosjekt" : "Endre prosjekt")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $visNyKunde) {
            NavigationStack {
                KundeSkjemaView(kunde: nil) { kunde in
                    prosjekt.kundeUUID = kunde.uuid
                    prosjekt.kundeNavn = kunde.navn
                }
            }
        }
        .toolbar {
            if erNy {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        context.insert(prosjekt)
                        dismiss()
                    }
                    .disabled(prosjekt.navn.trimmet.isEmpty)
                }
            }
        }
    }
}

struct TimeforingSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let prosjekt: Prosjekt
    @State private var foring: Timeforing
    private let erNy: Bool

    init(prosjekt: Prosjekt, foring: Timeforing?) {
        self.prosjekt = prosjekt
        _foring = State(initialValue: foring ?? Timeforing())
        erNy = foring == nil
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Dato", selection: $foring.dato, displayedComponents: .date)
                BelopFelt("Timer", belop: $foring.timer, enhet: "t")
                TextField("Hva gjorde du? (valgfritt)", text: $foring.notat, axis: .vertical)
                    .lineLimit(1...4)
            } footer: {
                Text("Halvtimer skriver du som 0,5. Notatet blir teksten på fakturalinjen.")
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle(erNy ? "Før timer" : "Endre timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if erNy {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        context.insert(foring)
                        foring.prosjekt = prosjekt
                        try? context.save()
                        dismiss()
                    }
                    .disabled(foring.timer <= 0)
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
    }
}
