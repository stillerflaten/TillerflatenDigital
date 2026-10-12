import SwiftUI
import SwiftData

/// En fast inntekt du fakturerer jevnlig, f.eks. en årlig lisens eller en månedlig driftsavtale.
@Model
final class Avtale {
    var uuid: UUID = UUID()
    /// Teksten på fakturalinjen, f.eks. «Lisens og support for medlemsside».
    var navn: String = ""
    var kundeUUID: UUID? = nil
    /// Kopi av kundens navn, så avtalen har et navn å vise selv om kunden slettes.
    var kundeNavn: String = ""
    /// Beløp per periode uten mva.
    var belop: Double = 0
    var intervallRaw: String = Trekkintervall.aarlig.rawValue
    /// Første dag i perioden som skal faktureres neste gang.
    var nestePeriodeFra: Date = Date.now
    /// Hvor mange dager før perioden starter fakturaen skal lages.
    var dagerFor: Int = 14
    var aktiv: Bool = true
    var notat: String = ""
    var opprettet: Date = Date.now
    /// Selve avtalen eller kontrakten, som PDF eller bilde.
    @Relationship(deleteRule: .cascade, inverse: \Dokument.avtale) var dokumenter: [Dokument]? = []

    init(navn: String = "") {
        self.navn = navn
    }

    var intervall: Trekkintervall {
        get { Trekkintervall(rawValue: intervallRaw) ?? .aarlig }
        set { intervallRaw = newValue.rawValue }
    }

    /// Siste dag i perioden som skal faktureres neste gang.
    var nestePeriodeTil: Date { Avtaler.periodeTil(fra: nestePeriodeFra, intervall: intervall) }

    /// Dagen du skal lage fakturaen.
    var nesteFakturadato: Date {
        Frister.kalender.date(byAdding: .day, value: -dagerFor, to: Frister.kalender.startOfDay(for: nestePeriodeFra))
            ?? nestePeriodeFra
    }

    var skalFaktureres: Bool {
        aktiv && nesteFakturadato <= Frister.kalender.startOfDay(for: .now)
    }

    /// Hva avtalen gir i året, uten mva.
    var perAar: Double { belop * Double(12 / intervall.maaneder) }
}

enum Avtaler {
    /// Om avtalen passer søketeksten: navn, kunde, notat eller navnet på et dokument.
    static func passer(_ avtale: Avtale, sok: String) -> Bool {
        let tekst = sok.trimmet
        guard !tekst.isEmpty else { return true }
        let felt = [avtale.navn, avtale.kundeNavn, avtale.notat] + (avtale.dokumenter ?? []).map(\.navn)
        return felt.contains { $0.localizedCaseInsensitiveContains(tekst) }
    }

    /// Siste dag i en periode som starter `fra`.
    static func periodeTil(fra: Date, intervall: Trekkintervall) -> Date {
        let kal = Frister.kalender
        let neste = kal.date(byAdding: .month, value: intervall.maaneder, to: kal.startOfDay(for: fra)) ?? fra
        return kal.date(byAdding: .day, value: -1, to: neste) ?? neste
    }

    /// «01.11.2026–31.10.2027»
    static func periodetekst(fra: Date, til: Date) -> String {
        var format = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Locale(identifier: "nb_NO"))
        format.timeZone = Frister.kalender.timeZone
        return "\(fra.formatted(format))–\(til.formatted(format))"
    }

    /// «Lisens og support, 01.11.2026–31.10.2027»
    static func linjetekst(navn: String, fra: Date, til: Date) -> String {
        "\(navn.trimmet), \(periodetekst(fra: fra, til: til))"
    }

    /// Lager et fakturautkast for neste periode og flytter avtalen fram én periode.
    @MainActor
    static func lagFaktura(for avtale: Avtale, kunde: Kunde?, context: ModelContext) -> Faktura {
        let f = Fakturering.nyttUtkast(context: context)
        if let kunde {
            Fakturering.kopier(kunde, til: f)
        } else {
            f.kundeNavn = avtale.kundeNavn
        }
        f.leveringsdato = avtale.nestePeriodeFra
        let linje = FakturaLinje(nr: 1, beskrivelse: linjetekst(navn: avtale.navn, fra: avtale.nestePeriodeFra, til: avtale.nestePeriodeTil),
                                 antall: 1, enhetspris: avtale.belop)
        context.insert(linje)
        f.linjer = [linje]
        avtale.nestePeriodeFra = Frister.kalender.date(byAdding: .month, value: avtale.intervall.maaneder, to: avtale.nestePeriodeFra)
            ?? avtale.nestePeriodeFra
        try? context.save()
        Varsler.planleggAvtale(avtale)
        return f
    }
}

// MARK: Visninger

struct AvtaleListeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Avtale.nestePeriodeFra) private var avtaler: [Avtale]
    @Query(sort: \Kunde.navn) private var kunder: [Kunde]

    @State private var visNy = false
    @State private var nyFaktura: Faktura?
    @State private var endre: Avtale?
    @State private var sok = ""

    /// Avtaler som passer søket, sortert etter når de skal faktureres.
    private var treff: [Avtale] {
        avtaler
            .filter { sok.isEmpty || Avtaler.passer($0, sok: sok) }
            .sorted { $0.nesteFakturadato < $1.nesteFakturadato }
    }
    private var klare: [Avtale] { treff.filter(\.skalFaktureres) }
    private var kommende: [Avtale] { treff.filter { $0.aktiv && !$0.skalFaktureres } }
    private var avsluttet: [Avtale] { treff.filter { !$0.aktiv }.sorted { $0.opprettet > $1.opprettet } }

    var body: some View {
        List {
            if avtaler.isEmpty {
                ContentUnavailableView {
                    Label("Ingen avtaler ennå", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Legg inn lisenser, driftsavtaler og annet du fakturerer jevnlig. Appen minner deg på når det er tid, og lager fakturautkastet med riktig periode.")
                } actions: {
                    Button("Legg inn den første") { visNy = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if treff.isEmpty {
                ContentUnavailableView.search(text: sok)
            }

            if !klare.isEmpty {
                Section {
                    ForEach(klare) { a in
                        KlarAvtaleRad(avtale: a, lagFaktura: {
                            nyFaktura = Avtaler.lagFaktura(for: a, kunde: kunder.first { $0.uuid == a.kundeUUID }, context: context)
                        }, endre: { endre = a })
                    }
                } header: {
                    Text("Skal faktureres nå")
                } footer: {
                    Text("Utkastet får perioden i linjeteksten, og avtalen flyttes fram til neste periode. Sletter du utkastet, kan du flytte datoen tilbake under avtalen.")
                }
            }

            if !kommende.isEmpty {
                Section {
                    ForEach(kommende) { a in
                        NavigationLink { AvtaleSkjemaView(avtale: a) } label: { AvtaleRad(avtale: a) }
                    }
                } header: {
                    HStack {
                        Text("Kommende")
                        Spacer()
                        Text("\(avtaler.filter(\.aktiv).reduce(0) { $0 + $1.perAar }.kr) i året")
                    }
                }
            }

            if !avsluttet.isEmpty {
                Section("Avsluttet") {
                    ForEach(avsluttet) { a in
                        NavigationLink { AvtaleSkjemaView(avtale: a) } label: { AvtaleRad(avtale: a) }
                    }
                }
            }
        }
        .temaBakgrunn()
        .navigationTitle("Avtaler")
        .searchable(text: $sok, prompt: "Søk i avtaler")
        .navigationDestination(item: $nyFaktura) { FakturaView(faktura: $0) }
        .toolbar {
            Button {
                visNy = true
            } label: {
                Label("Ny avtale", systemImage: "plus")
            }
        }
        .sheet(isPresented: $visNy) {
            NavigationStack {
                AvtaleSkjemaView(avtale: nil)
            }
        }
        // Ligger her og ikke i raden, så skjemaet ikke lukkes når avtalen flyttes ut av «Skal faktureres nå».
        .sheet(item: $endre) { a in
            NavigationStack {
                AvtaleSkjemaView(avtale: a)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Ferdig") { endre = nil }
                        }
                    }
            }
        }
    }
}

/// Rad for en avtale det er tid for å fakturere.
private struct KlarAvtaleRad: View {
    let avtale: Avtale
    let lagFaktura: () -> Void
    let endre: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AvtaleRad(avtale: avtale)
            HStack {
                Button(action: lagFaktura) {
                    Label("Lag fakturautkast", systemImage: "doc.richtext")
                }
                .buttonStyle(.borderedProminent)
                Button("Endre", action: endre)
                    .buttonStyle(.bordered)
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }
}

struct AvtaleRad: View {
    let avtale: Avtale

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(avtale.navn).lineLimit(1)
                Text(undertekst)
                    .font(.caption)
                    .foregroundStyle(avtale.skalFaktureres ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(avtale.belop.kr)
                .monospacedDigit()
        }
    }

    private var undertekst: String {
        var deler: [String] = []
        if !avtale.kundeNavn.isEmpty { deler.append(avtale.kundeNavn) }
        if !avtale.aktiv {
            deler.append("Avsluttet")
        } else {
            deler.append(avtale.intervall.navn)
            deler.append("faktureres \(avtale.nesteFakturadato.formatted(date: .abbreviated, time: .omitted))")
        }
        return deler.joined(separator: " · ")
    }
}

struct AvtaleSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Kunde.navn) private var kunder: [Kunde]

    @State private var avtale: Avtale
    @State private var visNyKunde = false
    @State private var bekreftSlett = false
    @State private var slettet = false
    private let erNy: Bool

    init(avtale: Avtale?) {
        _avtale = State(initialValue: avtale ?? Avtale())
        erNy = avtale == nil
    }

    var body: some View {
        Form {
            Section {
                TextField("Hva gjelder det? (f.eks. «Lisens og support for medlemsside»)", text: $avtale.navn, axis: .vertical)
                Picker("Kunde", selection: Binding(
                    get: { avtale.kundeUUID },
                    set: { id in
                        avtale.kundeUUID = id
                        avtale.kundeNavn = kunder.first { $0.uuid == id }?.navn ?? ""
                    })) {
                    Text("Velg kunde").tag(UUID?.none)
                    if let id = avtale.kundeUUID, !kunder.contains(where: { $0.uuid == id }) {
                        Text(avtale.kundeNavn).tag(Optional(id))
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
            } footer: {
                Text("Teksten blir fakturalinjen, med perioden etter.")
            }

            Section {
                BelopFelt("Beløp", belop: $avtale.belop)
                Picker("Faktureres", selection: $avtale.intervall) {
                    ForEach(Trekkintervall.allCases) { Text($0.navn).tag($0) }
                }
                DatePicker("Neste periode starter", selection: $avtale.nestePeriodeFra, displayedComponents: .date)
                Stepper("Fakturer \(avtale.dagerFor) dager før", value: $avtale.dagerFor, in: 0...60)
            } footer: {
                Text("Beløpet er uten mva. Neste faktura gjelder \(Avtaler.periodetekst(fra: avtale.nestePeriodeFra, til: avtale.nestePeriodeTil)), og lages \(avtale.nesteFakturadato.formatted(date: .long, time: .omitted)). Da får du et varsel.")
            }

            Section("Notater") {
                TextField("F.eks. hva support dekker, oppsigelsesfrist", text: $avtale.notat, axis: .vertical)
                    .lineLimit(2...8)
            }

            if erNy {
                Section {
                } footer: {
                    Text("Når avtalen er lagret, kan du legge ved selve kontrakten.")
                }
            } else {
                DokumentSeksjon(dokumenter: avtale.dokumenter ?? [], forklaring: "Legg ved den signerte avtalen eller kontrakten.",
                                leggTil: { avtale.dokumenter = (avtale.dokumenter ?? []) + [$0] },
                                fjern: { d in avtale.dokumenter?.removeAll { $0 == d } })

                Section {
                    Toggle("Aktiv", isOn: $avtale.aktiv)
                } footer: {
                    Text("Slå av når avtalen sies opp. Da får du ikke flere påminnelser.")
                }

                Section {
                    Button("Slett avtalen", role: .destructive) { bekreftSlett = true }
                        .confirmationDialog("Slette \(avtale.navn)?", isPresented: $bekreftSlett, titleVisibility: .visible) {
                            Button("Slett", role: .destructive) {
                                let a = avtale
                                slettet = true
                                Varsler.fjernAvtale(a)
                                dismiss()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(500))
                                    context.delete(a)
                                    try? context.save()
                                }
                            }
                        } message: {
                            Text("Dokumentene på avtalen slettes også. Fakturaer du har laget fra avtalen, blir ikke berørt.")
                        }
                }
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle(erNy ? "Ny avtale" : "Avtale")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if !erNy && !slettet { Varsler.planleggAvtale(avtale) }
        }
        .sheet(isPresented: $visNyKunde) {
            NavigationStack {
                KundeSkjemaView(kunde: nil) { kunde in
                    avtale.kundeUUID = kunde.uuid
                    avtale.kundeNavn = kunde.navn
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
                        context.insert(avtale)
                        let a = avtale
                        Task {
                            _ = await Varsler.beOmTillatelse()
                            Varsler.planleggAvtale(a)
                        }
                        dismiss()
                    }
                    .disabled(avtale.navn.trimmet.isEmpty)
                }
            }
        }
    }
}
