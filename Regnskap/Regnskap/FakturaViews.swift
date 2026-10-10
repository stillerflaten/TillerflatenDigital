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
        fakturaer.filter { $0.status == .betalt }.sorted { $0.nummer > $1.nummer }
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
                        Text(ubetalte.reduce(0) { $0 + $1.total }.kr)
                    }
                }
            }

            if !betalte.isEmpty {
                Section("Betalt") {
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
        let f = Faktura()
        f.forfallsdato = Calendar.current.date(byAdding: .day, value: Firma.lagretBetalingsfrist, to: f.fakturadato) ?? f.fakturadato
        f.mvaSats = UserDefaults.standard.bool(forKey: Innstilling.mvaRegistrert) ? 0.25 : 0
        context.insert(f)
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
                    case .sendt:
                        Text(faktura.erForfalt ? "Forfalt \(faktura.forfallsdato.formatted(date: .abbreviated, time: .omitted))"
                                               : "Forfaller \(faktura.forfallsdato.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(faktura.erForfalt ? Color.red : Color.secondary)
                    case .betalt:
                        Text("Betalt \((faktura.betaltDato ?? faktura.fakturadato).formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(Color.green)
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
            context.delete(f)
            try? context.save()
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
            if faktura.status == .utkast { faktura.mvaSats = mvaRegistrert ? 0.25 : 0 }
        }
        .navigationTitle(faktura.nummer > 0 ? "Faktura \(faktura.nummer)" : "Ny faktura")
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
                        RadVerdi("Føres som inntekt", faktura.sumEksMva.kr, uthevet: true)
                    } footer: {
                        Text(faktura.mvaBelop > 0
                             ? "Inntekten føres uten mva. Mva-en på \(faktura.mvaBelop.kr) skal betales videre til staten."
                             : "Beløpet legges inn under Inntekter med datoen pengene kom på konto.")
                    }
                }
                .navigationTitle("Registrer betaling")
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
            Text(sats > 0
                 ? "Du er mva-registrert, så 25 % mva legges på."
                 : "Du er ikke mva-registrert, så det legges ikke på mva. Fakturaen sier fra om det.")
        }

        Section("Merknad på fakturaen") {
            TextField("F.eks. «Takk for oppdraget!»", text: $faktura.merknad, axis: .vertical)
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
                }
            } message: {
                Text("Fakturaen får nummer og kan ikke endres etterpå. Så kan du sende den som PDF.")
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
        Section {
            FakturaForhandsvisning(faktura: faktura)
        }

        Section {
            if let pdf {
                ShareLink(item: pdf,
                          subject: Text("Faktura \(faktura.nummer) fra \(faktura.selgerNavn)"),
                          message: Text("Hei!\n\nVedlagt er faktura \(faktura.nummer) på \(Fakturering.kroner(faktura.total)), med forfall \(faktura.forfallsdato.formatted(date: .long, time: .omitted)).\n\nMed vennlig hilsen\n\(faktura.selgerEier)\n\(faktura.selgerNavn)")) {
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
            RadVerdi("Status", faktura.erForfalt ? "Forfalt" : faktura.status.navn)
            RadVerdi("Å betale", Fakturering.kroner(faktura.total), uthevet: true)
            if let betalt = faktura.betaltDato {
                RadVerdi("Betalt", betalt.formatted(date: .abbreviated, time: .omitted))
            }
            if faktura.status == .sendt {
                Button {
                    betaltDato = .now
                    visBetalt = true
                } label: {
                    Label("Kunden har betalt", systemImage: "checkmark.circle")
                }
            } else {
                Button("Angre betaling") { bekreftAngre = true }
                    .confirmationDialog("Angre betalingen?", isPresented: $bekreftAngre, titleVisibility: .visible) {
                        Button("Angre", role: .destructive) {
                            Fakturering.angreBetalt(faktura, context: context)
                        }
                    } message: {
                        Text("Fakturaen settes tilbake til ubetalt, og inntekten som ble lagt inn, slettes.")
                    }
            }
        } footer: {
            Text("Når kunden har betalt, legges beløpet automatisk inn under Inntekter. En sendt faktura skal ikke slettes eller endres. Er noe feil, rettes det med en kreditnota.")
        }

        if faktura.status == .sendt && erSisteFaktura {
            Section {
                Button("Slett fakturaen", role: .destructive) { bekreftSlettSendt = true }
                    .confirmationDialog("Slette faktura \(faktura.nummer)?", isPresented: $bekreftSlettSendt, titleVisibility: .visible) {
                        Button("Slett, den er ikke sendt til noen", role: .destructive) { slettOgLukk() }
                    } message: {
                        Text("Gjør dette bare hvis fakturaen aldri er sendt til en kunde, for eksempel når du har testet. Nummer \(faktura.nummer) blir ledig igjen.")
                    }
            } footer: {
                Text("Den siste fakturaen kan slettes hvis den ikke er sendt til noen. Da blir nummeret brukt på neste faktura, så serien får ikke hull.")
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
            FakturaSide(faktura: faktura)
                .scaleEffect(skala, anchor: .topLeading)
                .frame(width: FakturaSide.a4.width * skala, height: FakturaSide.a4.height * skala, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
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

            if !erNy {
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
                            Text("Fakturaer du har laget til kunden, blir ikke berørt.")
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
    @AppStorage(Firma.orgnr) private var orgnr = ""
    @AppStorage(Firma.kontonr) private var kontonr = ""
    @AppStorage(Firma.epost) private var epost = Firma.standardEpost
    @AppStorage(Firma.betalingsfrist) private var betalingsfrist = 14
    @AppStorage(Firma.startnummer) private var startnummer = 1

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
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle("Firmaopplysninger")
        .navigationBarTitleDisplayMode(.inline)
    }
}
