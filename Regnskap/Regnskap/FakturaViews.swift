import SwiftUI
import SwiftData

/// Alle fakturaer: utkast, de som venter på betaling, og betalte.
struct FakturaListeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Faktura.fakturadato, order: .reverse) private var fakturaer: [Faktura]

    @State private var ny: Faktura?

    private var utkast: [Faktura] { fakturaer.filter { $0.status == .utkast } }
    private var ubetalte: [Faktura] {
        fakturaer.filter { $0.status == .sendt }.sorted { $0.forfallsdato < $1.forfallsdato }
    }
    private var betalte: [Faktura] {
        fakturaer.filter { $0.status == .betalt || $0.status == .kreditert }.sorted { $0.nummer > $1.nummer }
    }

    var body: some View {
        List {
            if !Firma.mangler.isEmpty {
                Section {
                    NavigationLink {
                        FirmaView()
                    } label: {
                        Label("Fyll ut firmaopplysningene før du sender første faktura", systemImage: "building.2")
                    }
                }
            }

            if !dobleNummer.isEmpty {
                Section {
                    Label("Flere fakturaer har samme nummer (\(dobleNummer.map(String.init).joined(separator: ", "))). Det kan skje hvis du ferdigstilte fakturaer på to enheter samtidig. Ta kontakt med regnskapsfører om hvordan det bør rettes.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if fakturaer.isEmpty {
                ContentUnavailableView {
                    Label("Ingen fakturaer ennå", systemImage: "doc.richtext")
                } description: {
                    Text("Når du har gjort et oppdrag for en kunde, lager du fakturaen her. Appen nummererer den, lager PDF og fører inntekten når kunden har betalt.")
                } actions: {
                    Button("Lag første faktura") { nyFaktura() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if !utkast.isEmpty {
                Section("Utkast") {
                    ForEach(utkast) { f in
                        NavigationLink(value: f) { FakturaRad(faktura: f) }
                    }
                    .onDelete { indekser in
                        for i in indekser { context.delete(utkast[i]) }
                    }
                }
            }

            if !ubetalte.isEmpty {
                Section {
                    ForEach(ubetalte) { f in
                        NavigationLink(value: f) { FakturaRad(faktura: f) }
                    }
                } header: {
                    HStack {
                        Text("Venter på betaling")
                        Spacer()
                        Text(ubetalte.filter { !$0.erKreditnota }.reduce(0) { $0 + Fakturering.gjenstaar($1, context: context) }.kr)
                    }
                }
            }

            if !betalte.isEmpty {
                Section("Ferdig") {
                    ForEach(betalte) { f in
                        NavigationLink(value: f) { FakturaRad(faktura: f) }
                    }
                }
            }

            Section {
                NavigationLink {
                    KundeListeView()
                } label: {
                    Label("Kunder", systemImage: "person.2")
                }
                NavigationLink {
                    FirmaView()
                } label: {
                    Label("Firmaopplysninger", systemImage: "building.2")
                }
            } footer: {
                Text("Her endrer du kunder og opplysningene om deg som står på fakturaen. Endringene gjelder fakturaer du ferdigstiller etterpå.")
            }
        }
        .temaBakgrunn()
        .navigationTitle("Fakturaer")
        .onAppear(perform: ryddTommeUtkast)
        .navigationDestination(for: Faktura.self) { FakturaView(faktura: $0) }
        .navigationDestination(item: $ny) { FakturaView(faktura: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    KundeListeView()
                } label: {
                    Label("Kunder", systemImage: "person.2")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    nyFaktura()
                } label: {
                    Label("Ny faktura", systemImage: "plus")
                }
            }
        }
    }

    /// Utkast som ble opprettet, men aldri fylt ut, fjernes når du kommer tilbake til listen.
    private func ryddTommeUtkast() {
        for f in utkast where f.kundeUUID == nil && f.kundeNavn.isEmpty && f.sumEksMva == 0
            && f.merknad.isEmpty && f.sorterteLinjer.allSatisfy({ $0.beskrivelse.isEmpty }) {
            context.delete(f)
        }
    }

    private var dobleNummer: [Int] {
        Dictionary(grouping: fakturaer.filter { $0.nummer > 0 }, by: \.nummer)
            .filter { $0.value.count > 1 }
            .keys.sorted()
    }

    private func nyFaktura() {
        let f = Fakturering.nyttUtkast(context: context)
        let linje = FakturaLinje(nr: 1)
        context.insert(linje)
        f.linjer = [linje]
        ny = f
    }
}

struct FakturaRad: View {
    let faktura: Faktura

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(faktura.tittel)
                    .lineLimit(1)
                Group {
                    switch faktura.status {
                    case .utkast:
                        Text("Ikke sendt")
                    case .sendt where faktura.erKreditnota:
                        Text("Skal betales tilbake til kunden")
                            .foregroundStyle(Color.orange)
                    case .sendt where faktura.antallPurringer > 0:
                        Text("Purret, ny frist \(faktura.gjeldendeFrist.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(Color.red)
                    case .sendt:
                        Text(faktura.erForfalt ? "Forfalt \(faktura.forfallsdato.formatted(date: .abbreviated, time: .omitted))"
                                               : "Forfaller \(faktura.forfallsdato.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(faktura.erForfalt ? Color.red : Color.secondary)
                    case .betalt:
                        Text("\(faktura.erKreditnota ? "Betalt tilbake" : "Betalt") \((faktura.betaltDato ?? faktura.fakturadato).formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(Color.green)
                    case .kreditert:
                        Text(faktura.erKreditnota ? "Trukket fra faktura \(faktura.kreditererNummer)" : "Kreditert")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(faktura.total.kr)
                .monospacedDigit()
        }
    }
}

/// Én faktura. Utkast kan redigeres; sendte fakturaer vises som PDF og kan merkes som betalt.
struct FakturaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false
    @Query(sort: \Kunde.navn) private var kunder: [Kunde]
    @Query private var alleFakturaer: [Faktura]

    @Bindable var faktura: Faktura

    @State private var visNyKunde = false
    @State private var bekreftFerdigstill = false
    @State private var bekreftSlett = false
    @State private var visBetalt = false
    @State private var bekreftAngre = false
    @State private var bekreftSlettSendt = false
    @State private var betaltDato = Date.now
    @State private var pdf: URL?
    @State private var nyKreditnota: Faktura?
    @State private var bekreftKreditnota = false
    @State private var kalenderMelding: String?
    @State private var visPurring = false

    /// Bare den siste fakturaen kan slettes, så nummerserien ikke får hull.
    private var erSisteFaktura: Bool {
        faktura.nummer > 0 && faktura.nummer == alleFakturaer.map(\.nummer).max()
    }

    /// Går tilbake først, og sletter når skjermen er borte.
    private func slettOgLukk() {
        let f = faktura
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            Fakturering.slett(f, context: context)
        }
    }

    private var hva: String { faktura.erKreditnota ? "kreditnota" : "faktura" }

    private func leggForfallIKalender() async {
        guard await Kalender.beOmTilgang() else {
            kalenderMelding = Kalender.Feil.ingenTilgang.errorDescription
            return
        }
        do {
            try Kalender.leggInn(faktura: faktura)
            kalenderMelding = "Forfallet er lagt i kalenderen «\(Kalender.navn)». Det fjernes når du merker fakturaen som betalt."
        } catch {
            kalenderMelding = "Kunne ikke legge inn i kalenderen: \(error.localizedDescription)"
        }
    }

    private var valgtKunde: Kunde? {
        guard let id = faktura.kundeUUID else { return nil }
        return kunder.first(where: { $0.uuid == id })
    }

    var body: some View {
        Form {
            if faktura.status == .utkast {
                utkastSeksjoner
            } else {
                sendtSeksjoner
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .onAppear {
            // Et utkast følger mva-innstillingen til det ferdigstilles.
            if faktura.status == .utkast && !faktura.erKreditnota { faktura.mvaSats = mvaRegistrert ? 0.25 : 0 }
        }
        .navigationTitle(faktura.nummer > 0 ? "\(hva.capitalized) \(faktura.nummer)" : "Ny \(hva)")
        .navigationDestination(item: $nyKreditnota) { FakturaView(faktura: $0) }
        .alert("Kalender", isPresented: Binding(get: { kalenderMelding != nil }, set: { if !$0 { kalenderMelding = nil } })) {
            Button("OK") { kalenderMelding = nil }
        } message: {
            Text(kalenderMelding ?? "")
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $visNyKunde) {
            NavigationStack {
                KundeSkjemaView(kunde: nil) { kunde in
                    Fakturering.kopier(kunde, til: faktura)
                }
            }
        }
        .sheet(isPresented: $visBetalt) {
            NavigationStack {
                Form {
                    DatePicker("Betalt", selection: $betaltDato, displayedComponents: .date)
                    Section {
                        RadVerdi(faktura.erKreditnota ? "Trekkes fra inntektene" : "Føres som inntekt",
                                 Fakturering.inntektVedBetaling(faktura, context: context).kr, uthevet: true)
                    } footer: {
                        Text(faktura.erKreditnota
                             ? "Beløpet legges inn som en negativ inntekt, så årets inntekter blir riktige."
                             : faktura.mvaBelop > 0
                             ? "Inntekten føres uten mva. Mva-en på \(faktura.mvaBelop.kr) skal betales videre til staten."
                             : "Beløpet legges inn under Inntekter med datoen pengene kom på konto.")
                    }
                }
                .navigationTitle(faktura.erKreditnota ? "Registrer tilbakebetaling" : "Registrer betaling")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Avbryt") { visBetalt = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lagre") {
                            Fakturering.registrerBetalt(faktura, dato: betaltDato, context: context)
                            visBetalt = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: Utkast

    @ViewBuilder
    private var utkastSeksjoner: some View {
        let sats = faktura.mvaSats
        let mangler = Fakturering.mangler(i: faktura)

        Section {
            Picker("Kunde", selection: Binding(
                get: { faktura.kundeUUID },
                set: { id in
                    if let kunde = kunder.first(where: { $0.uuid == id }) {
                        Fakturering.kopier(kunde, til: faktura)
                    }
                })) {
                if faktura.kundeUUID == nil || valgtKunde == nil {
                    Text(faktura.kundeNavn.isEmpty ? "Velg kunde" : faktura.kundeNavn).tag(faktura.kundeUUID)
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
            if !faktura.kundeAdresse.isEmpty {
                Text(faktura.kundeAdresse)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Kunde")
        }

        Section("Datoer") {
            DatePicker("Fakturadato", selection: $faktura.fakturadato, displayedComponents: .date)
                .onChange(of: faktura.fakturadato) { _, ny in
                    faktura.forfallsdato = Calendar.current.date(byAdding: .day, value: Firma.lagretBetalingsfrist, to: ny) ?? ny
                }
            DatePicker("Levert", selection: $faktura.leveringsdato, displayedComponents: .date)
            DatePicker("Forfall", selection: $faktura.forfallsdato, in: faktura.fakturadato..., displayedComponents: .date)
        }

        ForEach(faktura.sorterteLinjer) { linje in
            Section {
                FakturaLinjeFelt(linje: linje)
                if faktura.sorterteLinjer.count > 1 {
                    Button("Fjern linjen", role: .destructive) {
                        faktura.linjer?.removeAll { $0.uuid == linje.uuid }
                        context.delete(linje)
                        for (i, l) in faktura.sorterteLinjer.enumerated() { l.nr = i + 1 }
                    }
                }
            } header: {
                Text("Linje \(linje.nr)")
            }
        }

        Section {
            Button {
                let nr = (faktura.sorterteLinjer.last?.nr ?? 0) + 1
                let linje = FakturaLinje(nr: nr)
                context.insert(linje)
                faktura.linjer = (faktura.linjer ?? []) + [linje]
            } label: {
                Label("Legg til linje", systemImage: "plus")
            }
        }

        Section {
            RadVerdi("Sum eks. mva", Fakturering.kroner(faktura.sumEksMva))
            if sats > 0 {
                RadVerdi("Mva 25 %", Fakturering.kroner(faktura.mvaBelop))
            }
            RadVerdi("Å betale", Fakturering.kroner(faktura.total), uthevet: true)
        } footer: {
            Text(faktura.erKreditnota
                 ? "Kreditnota for faktura \(faktura.kreditererNummer). Skriv beløpene som positive tall, så trekkes de fra. Fjern linjer som ikke skal krediteres."
                 : sats > 0
                 ? "Du er mva-registrert, så 25 % mva legges på."
                 : "Du er ikke mva-registrert, så det legges ikke på mva. Fakturaen sier fra om det.")
        }

        Section("Merknad på fakturaen") {
            TextField("F.eks. «Takk for oppdraget!»", text: $faktura.merknad, axis: .vertical)
        }

        if !faktura.erKreditnota {
            Section {
                Toggle("Legg ved takkebrev (side 2)", isOn: $faktura.medTakkebrev)
            } footer: {
                Text("Et personlig takkebrev som følger med fakturaen. Fint etter første oppdrag for en ny kunde. Teksten endrer du i Firmaopplysninger.")
            }
        }

        Section {
            NavigationLink {
                FakturaUtkastVisning(faktura: faktura)
            } label: {
                Label("Forhåndsvis PDF", systemImage: "doc.text.magnifyingglass")
            }
        } footer: {
            Text("Se hvordan fakturaen blir, uten at den får nummer. Fint for å teste.")
        }

        Section {
            if !mangler.isEmpty {
                ForEach(mangler, id: \.self) { m in
                    Label(m, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
                if !Firma.mangler.isEmpty {
                    NavigationLink("Fyll ut firmaopplysninger") { FirmaView() }
                }
            }
            Button {
                bekreftFerdigstill = true
            } label: {
                Label("Ferdigstill fakturaen", systemImage: "checkmark.seal")
            }
            .disabled(!mangler.isEmpty)
            .confirmationDialog("Ferdigstille fakturaen?", isPresented: $bekreftFerdigstill, titleVisibility: .visible) {
                Button("Ferdigstill som nr. \(Fakturering.nesteNummer(context))") {
                    Fakturering.ferdigstill(faktura, kunde: valgtKunde, mvaRegistrert: mvaRegistrert, context: context)
                    let f = faktura
                    Task {
                        _ = await Varsler.beOmTillatelse()
                        Fakturering.planleggVarsel(for: f)
                    }
                }
            } message: {
                Text("Den får nummer og kan ikke endres etterpå. Så kan du sende den som PDF.")
            }
        } footer: {
            Text("Fakturanummerene kommer i rekkefølge uten hull, slik loven krever. Et utkast får nummer først når du ferdigstiller det.")
        }

        Section {
            Button("Slett utkastet", role: .destructive) { bekreftSlett = true }
                .confirmationDialog("Slette utkastet?", isPresented: $bekreftSlett, titleVisibility: .visible) {
                    Button("Slett", role: .destructive) { slettOgLukk() }
                }
        }
    }

    // MARK: Sendt eller betalt

    @ViewBuilder
    private var sendtSeksjoner: some View {
        let kreditnotaer = faktura.erKreditnota ? [] : Fakturering.kreditnotaer(for: faktura, context: context)
        let gjenstaar = Fakturering.gjenstaar(faktura, context: context)

        Section {
            FakturaForhandsvisning(faktura: faktura)
        }

        Section {
            if let pdf {
                ShareLink(item: pdf,
                          subject: Text("\(hva.capitalized) \(faktura.nummer) fra \(faktura.selgerNavn)"),
                          message: Text(faktura.erKreditnota
                                        ? "Hei!\n\nVedlagt er kreditnota \(faktura.nummer) for faktura \(faktura.kreditererNummer), på \(Fakturering.kroner(-faktura.total)).\n\nMed vennlig hilsen\n\(faktura.selgerEier)\n\(faktura.selgerNavn)"
                                        : "Hei!\n\nVedlagt er faktura \(faktura.nummer) på \(Fakturering.kroner(faktura.total)), med forfall \(faktura.forfallsdato.formatted(date: .long, time: .omitted)).\n\nMed vennlig hilsen\n\(faktura.selgerEier)\n\(faktura.selgerNavn)")) {
                    Label("Send eller del PDF", systemImage: "paperplane")
                }
            } else {
                ProgressView()
            }
        } footer: {
            if !faktura.kundeEpost.isEmpty {
                Text("Velg Mail og send til \(faktura.kundeEpost).")
            }
        }
        .task(id: faktura.statusRaw) { pdf = FakturaPDF.fil(for: faktura) }

        Section {
            RadVerdi("Status", faktura.erForfalt ? "Forfalt" : statusTekst)
            if faktura.erKreditnota {
                RadVerdi("Kreditert", Fakturering.kroner(-faktura.total), uthevet: true)
            } else {
                RadVerdi("Fakturert", Fakturering.kroner(faktura.total), uthevet: kreditnotaer.isEmpty)
                ForEach(kreditnotaer) { k in
                    NavigationLink {
                        FakturaView(faktura: k)
                    } label: {
                        RadVerdi("Kreditnota \(k.nummer)", Fakturering.kroner(k.total))
                    }
                }
                if !kreditnotaer.isEmpty && faktura.status == .sendt {
                    RadVerdi("Gjenstår å betale", Fakturering.kroner(gjenstaar), uthevet: true)
                }
            }
            if let betalt = faktura.betaltDato {
                RadVerdi(faktura.erKreditnota ? "Betalt tilbake" : "Betalt", betalt.formatted(date: .abbreviated, time: .omitted))
            }
            if faktura.status == .sendt {
                Button {
                    betaltDato = .now
                    visBetalt = true
                } label: {
                    Label(faktura.erKreditnota ? "Pengene er betalt tilbake" : "Kunden har betalt", systemImage: "checkmark.circle")
                }
                if !faktura.erKreditnota {
                    Button {
                        Task { await leggForfallIKalender() }
                    } label: {
                        Label("Legg forfallet i kalenderen", systemImage: "calendar.badge.plus")
                    }
                }
            } else if faktura.status == .betalt {
                Button("Angre betaling") { bekreftAngre = true }
                    .confirmationDialog("Angre betalingen?", isPresented: $bekreftAngre, titleVisibility: .visible) {
                        Button("Angre", role: .destructive) {
                            Fakturering.angreBetalt(faktura, context: context)
                        }
                    } message: {
                        Text("Den settes tilbake til ubetalt, og inntekten som ble lagt inn, slettes.")
                    }
            }
        } footer: {
            if faktura.erKreditnota {
                Text(faktura.status == .kreditert
                     ? "Fakturaen var ikke betalt, så kreditnotaen er trukket fra det kunden skal betale."
                     : "Fakturaen var betalt. Når du har betalt pengene tilbake til kunden, trykker du på knappen over, så trekkes beløpet fra inntektene.")
            } else {
                Text("Du får et varsel dagen etter forfall hvis fakturaen ikke er merket som betalt. Når kunden har betalt, legges beløpet automatisk inn under Inntekter.")
            }
        }

        if !faktura.erKreditnota && faktura.status == .sendt && (faktura.erForfalt || faktura.antallPurringer > 0) {
            Section {
                if let dato = faktura.purreDato, let frist = faktura.purreFrist {
                    RadVerdi(faktura.antallPurringer > 1 ? "Purret \(faktura.antallPurringer) ganger, sist" : "Purret",
                             dato.formatted(date: .abbreviated, time: .omitted))
                    RadVerdi("Ny frist", frist.formatted(date: .abbreviated, time: .omitted))
                }
                Button {
                    visPurring = true
                } label: {
                    Label(faktura.antallPurringer == 0 ? "Send purring" : "Send ny purring", systemImage: "envelope.badge")
                }
            } header: {
                Text("Purring")
            } footer: {
                Text("En purring er en vennlig påminnelse med ny frist. Du får et nytt varsel dagen etter den nye fristen.")
            }
            .sheet(isPresented: $visPurring) {
                NavigationStack {
                    PurringView(faktura: faktura, belop: gjenstaar)
                }
            }
        }

        if !faktura.erKreditnota && (faktura.status == .sendt || faktura.status == .betalt) {
            Section {
                Button {
                    bekreftKreditnota = true
                } label: {
                    Label("Lag kreditnota", systemImage: "arrow.uturn.backward.circle")
                }
                .confirmationDialog("Lage kreditnota for faktura \(faktura.nummer)?", isPresented: $bekreftKreditnota, titleVisibility: .visible) {
                    Button("Lag kreditnota") {
                        nyKreditnota = Fakturering.lagKreditnota(for: faktura, context: context)
                    }
                } message: {
                    Text("Du får et utkast med de samme linjene. Fjern eller endre linjene hvis bare deler av fakturaen skal krediteres.")
                }
            } footer: {
                Text("En sendt faktura skal ikke slettes eller endres. Er noe feil, lager du en kreditnota og eventuelt en ny faktura.")
            }
        }

        if faktura.status != .betalt && erSisteFaktura {
            Section {
                Button("Slett \(hva)en", role: .destructive) { bekreftSlettSendt = true }
                    .confirmationDialog("Slette \(hva) \(faktura.nummer)?", isPresented: $bekreftSlettSendt, titleVisibility: .visible) {
                        Button("Slett, den er ikke sendt til noen", role: .destructive) { slettOgLukk() }
                    } message: {
                        Text("Gjør dette bare hvis den aldri er sendt til en kunde, for eksempel når du har testet. Nummer \(faktura.nummer) blir ledig igjen.")
                    }
            } footer: {
                Text("Den siste i nummerserien kan slettes hvis den ikke er sendt til noen. Da blir nummeret brukt på nytt, så serien får ikke hull.")
            }
        }
    }

    private var statusTekst: String {
        switch faktura.status {
        case .sendt where faktura.erKreditnota: "Skal betales tilbake"
        case .kreditert where faktura.erKreditnota: "Trukket fra faktura \(faktura.kreditererNummer)"
        case .betalt where faktura.erKreditnota: "Betalt tilbake"
        default: faktura.status.navn
        }
    }
}

/// Lager en purring på en forfalt faktura, med ny frist.
struct PurringView: View {
    @Environment(\.dismiss) private var dismiss
    let faktura: Faktura
    let belop: Double

    @State private var frist: Date
    @State private var pdf: URL?

    init(faktura: Faktura, belop: Double) {
        self.faktura = faktura
        self.belop = belop
        _frist = State(initialValue: Frister.kalender.date(byAdding: .day, value: 14, to: .now) ?? .now)
    }

    private var purring: FakturaSide.Purring {
        FakturaSide.Purring(nr: faktura.antallPurringer + 1, frist: frist, belop: belop)
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Ny frist", selection: $frist, in: Date.now..., displayedComponents: .date)
            } footer: {
                Text("14 dager er vanlig. Skal du senere sende saken til inkasso, må kunden ha fått minst 14 dager på seg etter purringen.")
            }

            Section {
                FakturaSide(faktura: faktura, purring: purring)
                    .scaleEffect(0.5, anchor: .topLeading)
                    .frame(width: FakturaSide.a4.width / 2, height: FakturaSide.a4.height / 2, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
            }

            Section {
                if let pdf {
                    ShareLink(item: pdf,
                              subject: Text("Påminnelse: faktura \(faktura.nummer) fra \(faktura.selgerNavn)"),
                              message: Text("Hei!\n\nVi kan ikke se å ha mottatt betaling for faktura \(faktura.nummer). Vedlagt er en påminnelse med ny frist \(frist.formatted(date: .long, time: .omitted)). Har du betalt nylig, kan du se bort fra denne.\n\nMed vennlig hilsen\n\(faktura.selgerEier)\n\(faktura.selgerNavn)")) {
                        Label("Send eller del purringen", systemImage: "paperplane")
                    }
                } else {
                    ProgressView()
                }
            } footer: {
                if !faktura.kundeEpost.isEmpty {
                    Text("Velg Mail og send til \(faktura.kundeEpost). Trykk Sendt når purringen er sendt.")
                }
            }
        }
        .navigationTitle(purring.nr > 1 ? "Purring \(purring.nr)" : "Purring")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: frist) { pdf = FakturaPDF.purrefil(for: faktura, purring: purring) }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sendt") {
                    faktura.antallPurringer += 1
                    faktura.purreDato = .now
                    faktura.purreFrist = frist
                    Fakturering.planleggVarsel(for: faktura)
                    dismiss()
                }
            }
        }
    }
}

/// Fakturaen i liten størrelse, slik den ser ut som PDF.
struct FakturaForhandsvisning: View {
    let faktura: Faktura
    private let skala: CGFloat = 0.52

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(spacing: 16) {
                FakturaSide(faktura: faktura)
                    .scaleEffect(skala, anchor: .topLeading)
                    .frame(width: FakturaSide.a4.width * skala, height: FakturaSide.a4.height * skala, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                if faktura.harTakkebrev {
                    TakkebrevSide(faktura: faktura)
                        .scaleEffect(skala, anchor: .topLeading)
                        .frame(width: FakturaSide.a4.width * skala, height: FakturaSide.a4.height * skala, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                }
            }
            Spacer(minLength: 0)
        }
        .listRowBackground(Color.clear)
    }
}

/// Forhåndsvisning av et utkast. Ingenting lagres, og fakturaen får ikke nummer.
struct FakturaUtkastVisning: View {
    let faktura: Faktura
    @State private var pdf: URL?

    var body: some View {
        List {
            Section {
                FakturaForhandsvisning(faktura: faktura)
            } footer: {
                Text("Dette er et utkast, merket UTKAST. Nummeret kommer når du ferdigstiller fakturaen.")
            }
            if let pdf {
                Section {
                    ShareLink(item: pdf) {
                        Label("Åpne eller del utkastet som PDF", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .temaBakgrunn()
        .navigationTitle("Forhåndsvisning")
        .navigationBarTitleDisplayMode(.inline)
        .task { pdf = FakturaPDF.fil(for: faktura) }
    }
}

/// Feltene for én fakturalinje.
struct FakturaLinjeFelt: View {
    @Bindable var linje: FakturaLinje

    var body: some View {
        TextField("Hva har du levert? (f.eks. «Utvikling av nettside»)", text: $linje.beskrivelse, axis: .vertical)
        BelopFelt("Antall", belop: $linje.antall, enhet: "")
        BelopFelt("Pris", belop: $linje.enhetspris)
        RadVerdi("Beløp", Fakturering.kroner(linje.belop))
    }
}

// MARK: Kunder

struct KundeListeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Kunde.navn) private var kunder: [Kunde]
    @State private var visNy = false

    var body: some View {
        List {
            if kunder.isEmpty {
                ContentUnavailableView("Ingen kunder ennå", systemImage: "person.2",
                                       description: Text("Legg inn kunder én gang, så slipper du å skrive adressen på hver faktura."))
            }
            ForEach(kunder) { k in
                NavigationLink {
                    KundeSkjemaView(kunde: k)
                } label: {
                    VStack(alignment: .leading) {
                        Text(k.navn)
                        if !k.epost.isEmpty {
                            Text(k.epost).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { indekser in
                for i in indekser { context.delete(kunder[i]) }
            }
        }
        .temaBakgrunn()
        .navigationTitle("Kunder")
        .toolbar {
            if !kunder.isEmpty {
                EditButton()
            }
            Button {
                visNy = true
            } label: {
                Label("Ny kunde", systemImage: "plus")
            }
        }
        .sheet(isPresented: $visNy) {
            NavigationStack {
                KundeSkjemaView(kunde: nil)
            }
        }
    }
}

struct KundeSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kunde: Kunde
    @State private var bekreftSlett = false
    private let erNy: Bool
    private let lagret: ((Kunde) -> Void)?

    init(kunde: Kunde?, lagret: ((Kunde) -> Void)? = nil) {
        _kunde = State(initialValue: kunde ?? Kunde())
        erNy = kunde == nil
        self.lagret = lagret
    }

    var body: some View {
        Form {
            Section {
                TextField("Navn (person eller bedrift)", text: $kunde.navn)
                TextField("Adresse, postnummer og sted", text: $kunde.adresse, axis: .vertical)
                    .lineLimit(2...4)
                TextField("E-post", text: $kunde.epost)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Org.nr. (hvis bedrift)", text: $kunde.orgnr)
                    .keyboardType(.numberPad)
            } footer: {
                Text("Endrer du en kunde, gjelder det nye fakturaer. Fakturaer som er sendt, beholder opplysningene de ble sendt med.")
            }

            Section {
                TextField("F.eks. kontaktperson, hva dere har avtalt, pris per time", text: $kunde.notat, axis: .vertical)
                    .lineLimit(3...10)
            } header: {
                Text("Notater")
            } footer: {
                Text("Bare for deg. Står ikke på fakturaen.")
            }

            if !erNy {
                DokumentSeksjon(dokumenter: kunde.dokumenter ?? [], forklaring: "F.eks. avtaler uten fast fakturering, tilbud eller databehandleravtale.",
                                leggTil: { kunde.dokumenter = (kunde.dokumenter ?? []) + [$0] },
                                fjern: { d in kunde.dokumenter?.removeAll { $0 == d } })

                Section {
                    Button("Slett kunden", role: .destructive) { bekreftSlett = true }
                        .confirmationDialog("Slette \(kunde.navn)?", isPresented: $bekreftSlett, titleVisibility: .visible) {
                            Button("Slett", role: .destructive) {
                                // Gå tilbake først, og slett når skjermen er borte.
                                let k = kunde
                                dismiss()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(500))
                                    context.delete(k)
                                    try? context.save()
                                }
                            }
                        } message: {
                            Text("Dokumentene på kunden slettes også. Fakturaer du har laget til kunden, blir ikke berørt.")
                        }
                }
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle(erNy ? "Ny kunde" : kunde.navn)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if erNy {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        context.insert(kunde)
                        lagret?(kunde)
                        dismiss()
                    }
                    .disabled(kunde.navn.trimmet.isEmpty)
                }
            }
        }
    }
}

// MARK: Firmaopplysninger

struct FirmaView: View {
    @AppStorage(Firma.navn) private var navn = Firma.standardNavn
    @AppStorage(Firma.eier) private var eier = ""
    @AppStorage(Firma.adresse) private var adresse = ""
    @AppStorage(Firma.orgnr) private var orgnr = Firma.standardOrgnr
    @AppStorage(Firma.kontonr) private var kontonr = ""
    @AppStorage(Firma.epost) private var epost = Firma.standardEpost
    @AppStorage(Firma.betalingsfrist) private var betalingsfrist = 14
    @AppStorage(Firma.startnummer) private var startnummer = 1
    @AppStorage(Firma.takketekst) private var takketekst = Firma.standardTakketekst

    @Query private var fakturaer: [Faktura]

    private var harSendtFaktura: Bool { fakturaer.contains { $0.nummer > 0 } }

    var body: some View {
        Form {
            Section {
                TextField("Navn på foretaket", text: $navn)
                TextField("Ditt navn", text: $eier)
                TextField("Adresse, postnummer og sted", text: $adresse, axis: .vertical)
                    .lineLimit(2...4)
                TextField("E-post", text: $epost)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Foretaket")
            }

            Section {
                TextField("Organisasjonsnummer (9 siffer)", text: $orgnr)
                    .keyboardType(.numberPad)
                if !orgnr.isEmpty && Fakturering.siffer(orgnr).count != 9 {
                    Text("Organisasjonsnummeret skal ha 9 siffer.").font(.footnote).foregroundStyle(.orange)
                }
                TextField("Kontonummer (11 siffer)", text: $kontonr)
                    .keyboardType(.numberPad)
                if !kontonr.isEmpty && Fakturering.siffer(kontonr).count != 11 {
                    Text("Kontonummeret skal ha 11 siffer.").font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("Organisasjonsnummeret finner du på brreg.no. Bruk gjerne en egen konto for foretaket, så er det enkelt å holde regnskapet adskilt fra privatøkonomien.")
            }

            Section {
                Stepper("Betalingsfrist: \(betalingsfrist) dager", value: $betalingsfrist, in: 7...60)
                Stepper("Første fakturanummer: \(startnummer)", value: $startnummer, in: 1...100_000)
                    .disabled(harSendtFaktura)
            } header: {
                Text("Fakturaer")
            } footer: {
                Text(harSendtFaktura
                     ? "Fakturanummerene fortsetter der du slapp."
                     : "Har du sendt fakturaer fra et annet program før, starter du på neste nummer etter det siste du brukte.")
            }

            Section {
                TextField("Takkebrev", text: $takketekst, axis: .vertical)
                    .lineLimit(6...20)
                if takketekst != Firma.standardTakketekst {
                    Button("Bruk standardteksten igjen") { takketekst = Firma.standardTakketekst }
                }
            } header: {
                Text("Takkebrev")
            } footer: {
                Text("Følger med som side 2 når du krysser av for takkebrev på en faktura. {kunde} byttes ut med kundens navn og {firma} med navnet på foretaket. Hilsenen med navnet ditt legges til automatisk.")
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle("Firmaopplysninger")
        .navigationBarTitleDisplayMode(.inline)
    }
}
