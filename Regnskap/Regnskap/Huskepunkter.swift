import SwiftUI
import SwiftData

/// Noe du selv vil bli minnet på en bestemt dato, f.eks. å søke om fornyelse av biervervet.
@Model
final class Huskepunkt {
    var uuid: UUID = UUID()
    var tittel: String = ""
    var notat: String = ""
    var dato: Date = Date.now
    /// Hvor mange dager før datoen varselet skal komme. 0 betyr på selve dagen.
    var dagerFor: Int = 7
    /// Kommer igjen hvert år, f.eks. en årlig fornyelse.
    var hvertAar: Bool = false
    var ferdig: Bool = false
    var opprettet: Date = Date.now
    /// Firmadokumenter som hører til, f.eks. vedtaket om bierverv.
    @Relationship(deleteRule: .nullify, inverse: \Dokument.huskepunkter) var dokumenter: [Dokument]? = []

    init(tittel: String = "", dato: Date = .now, dagerFor: Int = 7) {
        self.tittel = tittel
        self.dato = dato
        self.dagerFor = dagerFor
    }

    var dagerIgjen: Int {
        let cal = Frister.kalender
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: dato)).day ?? 0
    }

    var erForfalt: Bool { !ferdig && dagerIgjen < 0 }

    /// Datoen da varselet kommer (kl. 09.00).
    var varselDato: Date {
        Frister.kalender.date(byAdding: .day, value: -dagerFor, to: dato) ?? dato
    }

    /// Merker huskepunktet som gjort. Gjentas det hvert år, flyttes det til neste år i stedet.
    func merkFerdig() {
        if hvertAar {
            dato = Huskepunkter.nesteAar(etter: dato)
            ferdig = false
        } else {
            ferdig = true
        }
        Varsler.planleggHuskepunkt(self)
    }
}

enum Huskepunkter {
    /// Valgene i «Varsle meg»-menyen, i dager før.
    static let varselvalg: [(dager: Int, navn: String)] = [
        (0, "Samme dag"),
        (1, "1 dag før"),
        (7, "1 uke før"),
        (14, "2 uker før"),
        (30, "1 måned før"),
        (60, "2 måneder før"),
        (90, "3 måneder før"),
    ]

    static func varseltekst(_ dager: Int) -> String {
        varselvalg.first { $0.dager == dager }?.navn ?? "\(dager) dager før"
    }

    /// Samme dato neste år. Er det et år etter, men datoen fortsatt passert (f.eks. glemt i flere år), hoppes det fram til neste gang den kommer.
    static func nesteAar(etter dato: Date, idag: Date = .now) -> Date {
        let cal = Frister.kalender
        var neste = cal.date(byAdding: .year, value: 1, to: dato) ?? dato
        while cal.startOfDay(for: neste) < cal.startOfDay(for: idag) {
            neste = cal.date(byAdding: .year, value: 1, to: neste) ?? neste
        }
        return neste
    }

    /// Forslaget som vises når listen er tom.
    static func forslagBierverv() -> Huskepunkt {
        let h = Huskepunkt(tittel: "Søk om fornyelse av bierverv",
                           dato: Frister.kalender.date(from: DateComponents(year: 2028, month: 9, day: 19, hour: 12)) ?? .now,
                           dagerFor: 30)
        h.notat = "Biervervet gjelder til 19.10.2028. Søk om forlengelse i god tid. Har noe endret seg i arbeidet, må du søke på nytt."
        return h
    }

    /// Legger inn varsler for alle huskepunkter, f.eks. når appen åpnes. Da kommer også varsler for
    /// huskepunkter du har lagt inn på en annen enhet (de kommer over iCloud).
    @MainActor
    static func planleggAlle(_ context: ModelContext) {
        guard let alle = try? context.fetch(FetchDescriptor<Huskepunkt>()) else { return }
        Varsler.planleggHuskepunkter(alle)
    }
}

// MARK: Visninger

/// Seksjonen «Mine huskepunkter» øverst på Frister-siden.
struct HuskepunktSeksjon: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Huskepunkt.dato) private var alle: [Huskepunkt]

    let iKalender: Set<String>
    let leggIKalender: (Huskepunkt) -> Void
    let nytt: (Huskepunkt?) -> Void

    private var aktive: [Huskepunkt] { alle.filter { !$0.ferdig } }
    private var ferdige: [Huskepunkt] { alle.filter(\.ferdig).sorted { $0.dato > $1.dato } }
    private var harBierverv: Bool { alle.contains { $0.tittel.localizedCaseInsensitiveContains("bierverv") } }

    var body: some View {
        Section {
            ForEach(aktive) { h in
                Button {
                    nytt(h)
                } label: {
                    HuskepunktRad(huskepunkt: h, iKalender: iKalender.contains("husk-\(h.uuid.uuidString)"))
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .leading) {
                    Button {
                        h.merkFerdig()
                    } label: {
                        Label("Ferdig", systemImage: "checkmark")
                    }
                    .tint(.green)
                    Button {
                        leggIKalender(h)
                    } label: {
                        Label("Kalender", systemImage: "calendar.badge.plus")
                    }
                    .tint(Color.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button("Slett", systemImage: "trash", role: .destructive) { slett(h) }
                }
                .contextMenu {
                    Button(h.hvertAar ? "Ferdig for i år" : "Merk som ferdig", systemImage: "checkmark") { h.merkFerdig() }
                    Button("Legg i kalenderen", systemImage: "calendar.badge.plus") { leggIKalender(h) }
                    Button("Slett", systemImage: "trash", role: .destructive) { slett(h) }
                }
            }

            Button {
                nytt(nil)
            } label: {
                Label("Nytt huskepunkt", systemImage: "plus.circle")
            }

            if !harBierverv {
                Button {
                    let h = Huskepunkter.forslagBierverv()
                    context.insert(h)
                    try? context.save()
                    Task {
                        _ = await Varsler.beOmTillatelse()
                        Varsler.planleggHuskepunkt(h)
                    }
                } label: {
                    Label("Forslag: Søk om fornyelse av bierverv (19.09.2028)", systemImage: "lightbulb")
                        .font(.footnote)
                }
            }

            if !ferdige.isEmpty {
                DisclosureGroup("Ferdige (\(ferdige.count))") {
                    ForEach(ferdige) { h in
                        HuskepunktRad(huskepunkt: h)
                            .swipeActions(edge: .trailing) {
                                Button("Slett", systemImage: "trash", role: .destructive) { slett(h) }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    h.ferdig = false
                                    Varsler.planleggHuskepunkt(h)
                                } label: {
                                    Label("Ikke ferdig", systemImage: "arrow.uturn.backward")
                                }
                            }
                    }
                }
            }
        } header: {
            Text("Mine huskepunkter")
        } footer: {
            Text("Trykk på et huskepunkt for å endre det. Sveip til høyre for å merke det som ferdig eller legge det i kalenderen, og til venstre for å slette. Varselet kommer kl. 09.00, og en gang til på selve dagen.")
        }
    }

    private func slett(_ h: Huskepunkt) {
        Varsler.fjernHuskepunkt(h)
        Kalender.fjern(huskepunkt: h)
        context.delete(h)
        try? context.save()
    }
}

struct HuskepunktRad: View {
    let huskepunkt: Huskepunkt
    var iKalender = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: huskepunkt.ferdig ? "checkmark.circle.fill" : "bell")
                .frame(width: 28)
                .foregroundStyle(huskepunkt.ferdig ? Color.green : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(huskepunkt.tittel)
                        .strikethrough(huskepunkt.ferdig)
                    if !(huskepunkt.dokumenter ?? []).isEmpty {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Har dokumenter")
                    }
                    if huskepunkt.hvertAar {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Hvert år")
                    }
                    if iKalender {
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Lagt i kalenderen")
                    }
                }
                if !huskepunkt.notat.isEmpty {
                    Text(huskepunkt.notat)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !huskepunkt.ferdig {
                    Text("Varsel: \(Huskepunkter.varseltekst(huskepunkt.dagerFor).lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(huskepunkt.dato.formatted(.dateTime.day().month(.abbreviated).year()))
                    .fontWeight(.medium)
                if !huskepunkt.ferdig {
                    Text(dagertekst)
                        .font(.caption)
                        .foregroundStyle(huskepunkt.dagerIgjen <= 7 ? Color.orange : Color.secondary)
                }
            }
        }
    }

    private var dagertekst: String {
        let d = huskepunkt.dagerIgjen
        if d < 0 { return "for \(-d) d siden" }
        if d == 0 { return "i dag" }
        return "om \(d) d"
    }
}

struct HuskepunktSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var huskepunkt: Huskepunkt
    @State private var egetAntall: Bool
    @State private var bekreftSlett = false
    @State private var slettet = false
    private let erNy: Bool

    init(huskepunkt: Huskepunkt?) {
        let h = huskepunkt ?? Huskepunkt()
        _huskepunkt = State(initialValue: h)
        _egetAntall = State(initialValue: !Huskepunkter.varselvalg.contains { $0.dager == h.dagerFor })
        erNy = huskepunkt == nil
    }

    /// -1 betyr «eget antall dager».
    private var varselvalg: Binding<Int> {
        Binding {
            egetAntall ? -1 : huskepunkt.dagerFor
        } set: { ny in
            if ny == -1 {
                egetAntall = true
            } else {
                egetAntall = false
                huskepunkt.dagerFor = ny
            }
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Hva skal du huske?", text: $huskepunkt.tittel)
                TextField("Notat (valgfritt)", text: $huskepunkt.notat, axis: .vertical)
                DatePicker("Dato", selection: $huskepunkt.dato, displayedComponents: .date)
            }

            Section {
                Picker("Varsle meg", selection: varselvalg) {
                    ForEach(Huskepunkter.varselvalg, id: \.dager) { Text($0.navn).tag($0.dager) }
                    Text("Eget antall dager").tag(-1)
                }
                if egetAntall {
                    Stepper("\(huskepunkt.dagerFor) dager før", value: $huskepunkt.dagerFor, in: 1...365)
                }
                Toggle("Gjenta hvert år", isOn: $huskepunkt.hvertAar)
            } footer: {
                Text(varselforklaring)
            }

            if erNy {
                Section {
                } footer: {
                    Text("Når du har lagret huskepunktet, kan du legge ved dokumenter, f.eks. et vedtak eller en avtale.")
                }
            } else {
                HuskepunktDokumentSeksjon(huskepunkt: huskepunkt)
            }

            if !erNy {
                Section {
                    Toggle("Ferdig", isOn: $huskepunkt.ferdig)
                }

                Section {
                    Button("Slett", role: .destructive) { bekreftSlett = true }
                        .confirmationDialog("Slette «\(huskepunkt.tittel)»?", isPresented: $bekreftSlett, titleVisibility: .visible) {
                            Button("Slett", role: .destructive) {
                                let h = huskepunkt
                                slettet = true
                                Varsler.fjernHuskepunkt(h)
                                Kalender.fjern(huskepunkt: h)
                                dismiss()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(500))
                                    context.delete(h)
                                    try? context.save()
                                }
                            }
                        } message: {
                            Text((huskepunkt.dokumenter ?? []).isEmpty ? "" : "Dokumentene blir liggende under Firmadokumenter.")
                        }
                }
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle(erNy ? "Nytt huskepunkt" : huskepunkt.tittel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if erNy {
                    Button("Avbryt") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(erNy ? "Lagre" : "Ferdig") {
                    if erNy { context.insert(huskepunkt) }
                    try? context.save()
                    let h = huskepunkt
                    Task {
                        _ = await Varsler.beOmTillatelse()
                        Varsler.planleggHuskepunkt(h)
                    }
                    dismiss()
                }
                .disabled(huskepunkt.tittel.trimmet.isEmpty)
            }
        }
        .onDisappear {
            if !erNy && !slettet { Varsler.planleggHuskepunkt(huskepunkt) }
        }
    }

    private var varselforklaring: String {
        let dato = huskepunkt.dato.formatted(date: .long, time: .omitted)
        let varsel = huskepunkt.varselDato.formatted(date: .long, time: .omitted)
        let tekst = huskepunkt.dagerFor == 0
            ? "Du får et varsel kl. 09.00 den \(dato)."
            : "Du får et varsel kl. 09.00 den \(varsel), og et til på selve dagen."
        return tekst + (huskepunkt.hvertAar ? " Når du merker det som ferdig, flyttes det til samme dato neste år." : "")
    }
}
