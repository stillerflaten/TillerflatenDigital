import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// En komplett kopi av alt i appen, inkludert bilder, lagret som én fil.
/// Filen kan legges i iCloud Drive (eller hvor som helst) og leses inn igjen.
struct Sikkerhetskopi: Codable {
    var versjon = 1
    var laget = Date.now
    var bilag: [BilagKopi] = []
    var inntekter: [InntektKopi] = []
    var driftsmidler: [DriftsmiddelKopi] = []
    var turer: [KjoreturKopi] = []
    var innstillinger: InnstillingerKopi?
    // Kom med i en senere versjon, derfor valgfrie (eldre kopier har dem ikke).
    var kunder: [KundeKopi]?
    var fakturaer: [FakturaKopi]?
    var fasteUtgifter: [FastUtgiftKopi]?
    var prosjekter: [ProsjektKopi]? = nil
    var avtaler: [AvtaleKopi]? = nil

    struct VedleggKopi: Codable {
        var uuid: UUID
        var opprettet: Date
        var nr: Int
        var data: Data?
    }

    struct BilagKopi: Codable {
        var uuid: UUID
        var dato: Date
        var tittel: String
        var belop: Double
        var mva: Double
        var kategoriRaw: String
        var naeringsandel: Double
        var notat: String
        var erRegning: Bool
        var forfallsdato: Date?
        var erBetalt: Bool
        var vedlegg: [VedleggKopi]
        var fraUtlandet: Bool? = nil
    }

    struct InntektKopi: Codable {
        var uuid: UUID
        var dato: Date
        var belop: Double
        var kilde: String
        var notat: String
        var bilde: Data?
    }

    struct DriftsmiddelKopi: Codable {
        var uuid: UUID
        var navn: String
        var kjopsdato: Date
        var kostpris: Double
        var gruppeRaw: String
        var naeringsandel: Double
        var levetidMinst3Aar: Bool
        var notat: String
    }

    struct KjoreturKopi: Codable {
        var uuid: UUID
        var dato: Date
        var fra: String
        var til: String
        var formal: String
        var km: Double
    }

    struct InnstillingerKopi: Codable {
        var lonn: Double
        var mvaRegistrert: Bool
        var mvaAarstermin: Bool
        var forskuddsskatt: Bool
        var hjemmekontor: Bool
        var firmaNavn: String?
        var firmaEier: String?
        var firmaAdresse: String?
        var firmaOrgnr: String?
        var firmaKontonr: String?
        var firmaEpost: String?
        var betalingsfrist: Int?
        var startnummer: Int?
        var mvaFra: Double? = nil
        var takketekst: String? = nil
    }

    struct KundeKopi: Codable {
        var uuid: UUID
        var navn: String
        var adresse: String
        var orgnr: String
        var epost: String
        var opprettet: Date
        var notat: String?
        var dokumenter: [DokumentKopi]? = nil
    }

    struct DokumentKopi: Codable {
        var uuid: UUID
        var navn: String
        var filtype: String
        var opprettet: Date
        var data: Data?

        init(_ d: Dokument) {
            uuid = d.uuid
            navn = d.navn
            filtype = d.filtype
            opprettet = d.opprettet
            data = d.data
        }

        /// Lager dokumentet i databasen, eller nil hvis filen mangler.
        func gjenopprett(i context: ModelContext) -> Dokument? {
            guard let data else { return nil }
            let d = Dokument(navn: navn, filtype: filtype, data: data)
            d.uuid = uuid
            d.opprettet = opprettet
            context.insert(d)
            return d
        }
    }

    struct FastUtgiftKopi: Codable {
        var uuid: UUID
        var navn: String
        var belop: Double
        var kategoriRaw: String
        var intervallRaw: String
        var nesteTrekk: Date
        var naeringsandel: Double
        var aktiv: Bool
        var notat: String
        var fraUtlandet: Bool? = nil
    }

    struct TimeforingKopi: Codable {
        var uuid: UUID
        var dato: Date
        var timer: Double
        var notat: String
        var fakturaUUID: UUID?
    }

    struct ProsjektKopi: Codable {
        var uuid: UUID
        var navn: String
        var kundeUUID: UUID?
        var kundeNavn: String
        var erFastpris: Bool
        var timepris: Double
        var fastpris: Double
        var ferdig: Bool
        var opprettet: Date
        var notat: String
        var foringer: [TimeforingKopi]
    }

    struct AvtaleKopi: Codable {
        var uuid: UUID
        var navn: String
        var kundeUUID: UUID?
        var kundeNavn: String
        var belop: Double
        var intervallRaw: String
        var nestePeriodeFra: Date
        var dagerFor: Int
        var aktiv: Bool
        var notat: String
        var opprettet: Date
        var dokumenter: [DokumentKopi]? = nil
    }

    struct LinjeKopi: Codable {
        var uuid: UUID
        var nr: Int
        var beskrivelse: String
        var antall: Double
        var enhetspris: Double
    }

    struct FakturaKopi: Codable {
        var uuid: UUID
        var nummer: Int
        var statusRaw: String
        var fakturadato: Date
        var forfallsdato: Date
        var leveringsdato: Date
        var betaltDato: Date?
        var mvaSats: Double
        var merknad: String
        var kundeUUID: UUID?
        var kundeNavn: String
        var kundeAdresse: String
        var kundeOrgnr: String
        var kundeEpost: String
        var selgerNavn: String
        var selgerEier: String
        var selgerAdresse: String
        var selgerOrgnr: String
        var selgerKontonr: String
        var selgerEpost: String
        var inntektUUID: UUID?
        var linjer: [LinjeKopi]
        var kreditererUUID: UUID?
        var kreditererNummer: Int?
        var antallPurringer: Int? = nil
        var purreDato: Date? = nil
        var purreFrist: Date? = nil
        var medTakkebrev: Bool? = nil
        var takketekst: String? = nil
    }

    // MARK: Lage kopi

    static func lag(fra context: ModelContext) throws -> Sikkerhetskopi {
        var kopi = Sikkerhetskopi()
        kopi.bilag = try context.fetch(FetchDescriptor<Bilag>()).map { b in
            BilagKopi(uuid: b.uuid, dato: b.dato, tittel: b.tittel, belop: b.belop, mva: b.mva,
                      kategoriRaw: b.kategoriRaw, naeringsandel: b.naeringsandel, notat: b.notat,
                      erRegning: b.erRegning, forfallsdato: b.forfallsdato, erBetalt: b.erBetalt,
                      vedlegg: b.sorterteVedlegg.map { VedleggKopi(uuid: $0.uuid, opprettet: $0.opprettet, nr: $0.nr, data: $0.data) },
                      fraUtlandet: b.fraUtlandet)
        }
        kopi.inntekter = try context.fetch(FetchDescriptor<Inntekt>()).map {
            InntektKopi(uuid: $0.uuid, dato: $0.dato, belop: $0.belop, kilde: $0.kilde, notat: $0.notat, bilde: $0.bilde)
        }
        kopi.driftsmidler = try context.fetch(FetchDescriptor<Driftsmiddel>()).map {
            DriftsmiddelKopi(uuid: $0.uuid, navn: $0.navn, kjopsdato: $0.kjopsdato, kostpris: $0.kostpris,
                             gruppeRaw: $0.gruppeRaw, naeringsandel: $0.naeringsandel,
                             levetidMinst3Aar: $0.levetidMinst3Aar, notat: $0.notat)
        }
        kopi.turer = try context.fetch(FetchDescriptor<Kjoretur>()).map {
            KjoreturKopi(uuid: $0.uuid, dato: $0.dato, fra: $0.fra, til: $0.til, formal: $0.formal, km: $0.km)
        }
        let d = UserDefaults.standard
        kopi.innstillinger = InnstillingerKopi(
            lonn: d.double(forKey: Innstilling.lonn),
            mvaRegistrert: d.bool(forKey: Innstilling.mvaRegistrert),
            mvaAarstermin: d.bool(forKey: Innstilling.mvaAarstermin),
            forskuddsskatt: d.object(forKey: Innstilling.forskuddsskatt) as? Bool ?? true,
            hjemmekontor: d.bool(forKey: Innstilling.hjemmekontor),
            firmaNavn: Firma.lagretNavn,
            firmaEier: d.string(forKey: Firma.eier),
            firmaAdresse: d.string(forKey: Firma.adresse),
            firmaOrgnr: d.string(forKey: Firma.orgnr),
            firmaKontonr: d.string(forKey: Firma.kontonr),
            firmaEpost: Firma.lagretEpost,
            betalingsfrist: Firma.lagretBetalingsfrist,
            startnummer: Firma.lagretStartnummer,
            mvaFra: d.double(forKey: Innstilling.mvaFra),
            takketekst: d.string(forKey: Firma.takketekst))
        kopi.kunder = try context.fetch(FetchDescriptor<Kunde>()).map {
            KundeKopi(uuid: $0.uuid, navn: $0.navn, adresse: $0.adresse, orgnr: $0.orgnr, epost: $0.epost,
                      opprettet: $0.opprettet, notat: $0.notat, dokumenter: ($0.dokumenter ?? []).map(DokumentKopi.init))
        }
        kopi.fasteUtgifter = try context.fetch(FetchDescriptor<FastUtgift>()).map {
            FastUtgiftKopi(uuid: $0.uuid, navn: $0.navn, belop: $0.belop, kategoriRaw: $0.kategoriRaw,
                           intervallRaw: $0.intervallRaw, nesteTrekk: $0.nesteTrekk, naeringsandel: $0.naeringsandel,
                           aktiv: $0.aktiv, notat: $0.notat, fraUtlandet: $0.fraUtlandet)
        }
        kopi.fakturaer = try context.fetch(FetchDescriptor<Faktura>()).map { f in
            FakturaKopi(uuid: f.uuid, nummer: f.nummer, statusRaw: f.statusRaw, fakturadato: f.fakturadato,
                        forfallsdato: f.forfallsdato, leveringsdato: f.leveringsdato, betaltDato: f.betaltDato,
                        mvaSats: f.mvaSats, merknad: f.merknad, kundeUUID: f.kundeUUID, kundeNavn: f.kundeNavn,
                        kundeAdresse: f.kundeAdresse, kundeOrgnr: f.kundeOrgnr, kundeEpost: f.kundeEpost,
                        selgerNavn: f.selgerNavn, selgerEier: f.selgerEier, selgerAdresse: f.selgerAdresse,
                        selgerOrgnr: f.selgerOrgnr, selgerKontonr: f.selgerKontonr, selgerEpost: f.selgerEpost,
                        inntektUUID: f.inntektUUID,
                        linjer: f.sorterteLinjer.map {
                            LinjeKopi(uuid: $0.uuid, nr: $0.nr, beskrivelse: $0.beskrivelse,
                                      antall: $0.antall, enhetspris: $0.enhetspris)
                        },
                        kreditererUUID: f.kreditererUUID, kreditererNummer: f.kreditererNummer,
                        antallPurringer: f.antallPurringer, purreDato: f.purreDato, purreFrist: f.purreFrist,
                        medTakkebrev: f.medTakkebrev, takketekst: f.takketekst)
        }
        kopi.avtaler = try context.fetch(FetchDescriptor<Avtale>()).map {
            AvtaleKopi(uuid: $0.uuid, navn: $0.navn, kundeUUID: $0.kundeUUID, kundeNavn: $0.kundeNavn, belop: $0.belop,
                       intervallRaw: $0.intervallRaw, nestePeriodeFra: $0.nestePeriodeFra, dagerFor: $0.dagerFor,
                       aktiv: $0.aktiv, notat: $0.notat, opprettet: $0.opprettet,
                       dokumenter: ($0.dokumenter ?? []).map(DokumentKopi.init))
        }
        kopi.prosjekter = try context.fetch(FetchDescriptor<Prosjekt>()).map { p in
            ProsjektKopi(uuid: p.uuid, navn: p.navn, kundeUUID: p.kundeUUID, kundeNavn: p.kundeNavn,
                         erFastpris: p.erFastpris, timepris: p.timepris, fastpris: p.fastpris, ferdig: p.ferdig,
                         opprettet: p.opprettet, notat: p.notat,
                         foringer: (p.foringer ?? []).map {
                             TimeforingKopi(uuid: $0.uuid, dato: $0.dato, timer: $0.timer, notat: $0.notat,
                                            fakturaUUID: $0.fakturaUUID)
                         })
        }
        return kopi
    }

    func somData() throws -> Data {
        let koder = JSONEncoder()
        koder.dateEncodingStrategy = .iso8601
        return try koder.encode(self)
    }

    static func les(_ data: Data) throws -> Sikkerhetskopi {
        let dekoder = JSONDecoder()
        dekoder.dateDecodingStrategy = .iso8601
        return try dekoder.decode(Sikkerhetskopi.self, from: data)
    }

    // MARK: Gjenopprette

    struct Resultat {
        var lagtTil = 0
        var hoppetOver = 0
    }

    /// Legger inn alt fra kopien som ikke allerede finnes i appen.
    /// Ingenting som finnes fra før, blir endret eller slettet.
    @MainActor
    func gjenopprett(til context: ModelContext) throws -> Resultat {
        var resultat = Resultat()

        let finnesBilag = Set(try context.fetch(FetchDescriptor<Bilag>()).map(\.uuid))
        for k in bilag {
            guard !finnesBilag.contains(k.uuid) else { resultat.hoppetOver += 1; continue }
            let b = Bilag(dato: k.dato, tittel: k.tittel, belop: k.belop)
            b.uuid = k.uuid
            b.mva = k.mva
            b.kategoriRaw = k.kategoriRaw
            b.naeringsandel = k.naeringsandel
            b.notat = k.notat
            b.erRegning = k.erRegning
            b.forfallsdato = k.forfallsdato
            b.erBetalt = k.erBetalt
            b.fraUtlandet = k.fraUtlandet ?? false
            context.insert(b)
            var nye: [Vedlegg] = []
            for vk in k.vedlegg {
                guard let data = vk.data else { continue }
                let v = Vedlegg(data: data, nr: vk.nr)
                v.uuid = vk.uuid
                v.opprettet = vk.opprettet
                context.insert(v)
                nye.append(v)
            }
            b.vedlegg = nye
            resultat.lagtTil += 1
        }

        let finnesInntekt = Set(try context.fetch(FetchDescriptor<Inntekt>()).map(\.uuid))
        for k in inntekter {
            guard !finnesInntekt.contains(k.uuid) else { resultat.hoppetOver += 1; continue }
            let i = Inntekt(dato: k.dato, belop: k.belop, kilde: k.kilde)
            i.uuid = k.uuid
            i.notat = k.notat
            i.bilde = k.bilde
            context.insert(i)
            resultat.lagtTil += 1
        }

        let finnesDriftsmiddel = Set(try context.fetch(FetchDescriptor<Driftsmiddel>()).map(\.uuid))
        for k in driftsmidler {
            guard !finnesDriftsmiddel.contains(k.uuid) else { resultat.hoppetOver += 1; continue }
            let d = Driftsmiddel(navn: k.navn, kjopsdato: k.kjopsdato, kostpris: k.kostpris)
            d.uuid = k.uuid
            d.gruppeRaw = k.gruppeRaw
            d.naeringsandel = k.naeringsandel
            d.levetidMinst3Aar = k.levetidMinst3Aar
            d.notat = k.notat
            context.insert(d)
            resultat.lagtTil += 1
        }

        let finnesTur = Set(try context.fetch(FetchDescriptor<Kjoretur>()).map(\.uuid))
        for k in turer {
            guard !finnesTur.contains(k.uuid) else { resultat.hoppetOver += 1; continue }
            let t = Kjoretur(dato: k.dato, fra: k.fra, til: k.til, formal: k.formal, km: k.km)
            t.uuid = k.uuid
            context.insert(t)
            resultat.lagtTil += 1
        }

        let finnesKunde = Set(try context.fetch(FetchDescriptor<Kunde>()).map(\.uuid))
        for k in kunder ?? [] {
            guard !finnesKunde.contains(k.uuid) else { resultat.hoppetOver += 1; continue }
            let kunde = Kunde(navn: k.navn)
            kunde.uuid = k.uuid
            kunde.adresse = k.adresse
            kunde.orgnr = k.orgnr
            kunde.epost = k.epost
            kunde.opprettet = k.opprettet
            kunde.notat = k.notat ?? ""
            context.insert(kunde)
            kunde.dokumenter = (k.dokumenter ?? []).compactMap { $0.gjenopprett(i: context) }
            resultat.lagtTil += 1
        }

        let finnesFaktura = Set(try context.fetch(FetchDescriptor<Faktura>()).map(\.uuid))
        for k in fakturaer ?? [] {
            guard !finnesFaktura.contains(k.uuid) else { resultat.hoppetOver += 1; continue }
            let f = Faktura()
            f.uuid = k.uuid
            f.nummer = k.nummer
            f.statusRaw = k.statusRaw
            f.fakturadato = k.fakturadato
            f.forfallsdato = k.forfallsdato
            f.leveringsdato = k.leveringsdato
            f.betaltDato = k.betaltDato
            f.mvaSats = k.mvaSats
            f.merknad = k.merknad
            f.kundeUUID = k.kundeUUID
            f.kundeNavn = k.kundeNavn
            f.kundeAdresse = k.kundeAdresse
            f.kundeOrgnr = k.kundeOrgnr
            f.kundeEpost = k.kundeEpost
            f.selgerNavn = k.selgerNavn
            f.selgerEier = k.selgerEier
            f.selgerAdresse = k.selgerAdresse
            f.selgerOrgnr = k.selgerOrgnr
            f.selgerKontonr = k.selgerKontonr
            f.selgerEpost = k.selgerEpost
            f.inntektUUID = k.inntektUUID
            f.kreditererUUID = k.kreditererUUID
            f.kreditererNummer = k.kreditererNummer ?? 0
            f.antallPurringer = k.antallPurringer ?? 0
            f.purreDato = k.purreDato
            f.purreFrist = k.purreFrist
            f.medTakkebrev = k.medTakkebrev ?? false
            f.takketekst = k.takketekst ?? ""
            context.insert(f)
            var nye: [FakturaLinje] = []
            for lk in k.linjer {
                let l = FakturaLinje(nr: lk.nr, beskrivelse: lk.beskrivelse, antall: lk.antall, enhetspris: lk.enhetspris)
                l.uuid = lk.uuid
                context.insert(l)
                nye.append(l)
            }
            f.linjer = nye
            resultat.lagtTil += 1
        }

        let finnesFast = Set(try context.fetch(FetchDescriptor<FastUtgift>()).map(\.uuid))
        for k in fasteUtgifter ?? [] {
            guard !finnesFast.contains(k.uuid) else { resultat.hoppetOver += 1; continue }
            let u = FastUtgift(navn: k.navn)
            u.uuid = k.uuid
            u.belop = k.belop
            u.kategoriRaw = k.kategoriRaw
            u.intervallRaw = k.intervallRaw
            u.nesteTrekk = k.nesteTrekk
            u.naeringsandel = k.naeringsandel
            u.aktiv = k.aktiv
            u.notat = k.notat
            u.fraUtlandet = k.fraUtlandet ?? false
            context.insert(u)
            Varsler.planleggFastUtgift(u)
            resultat.lagtTil += 1
        }

        let finnesAvtale = Set(try context.fetch(FetchDescriptor<Avtale>()).map(\.uuid))
        for k in avtaler ?? [] {
            guard !finnesAvtale.contains(k.uuid) else { resultat.hoppetOver += 1; continue }
            let a = Avtale(navn: k.navn)
            a.uuid = k.uuid
            a.kundeUUID = k.kundeUUID
            a.kundeNavn = k.kundeNavn
            a.belop = k.belop
            a.intervallRaw = k.intervallRaw
            a.nestePeriodeFra = k.nestePeriodeFra
            a.dagerFor = k.dagerFor
            a.aktiv = k.aktiv
            a.notat = k.notat
            a.opprettet = k.opprettet
            context.insert(a)
            a.dokumenter = (k.dokumenter ?? []).compactMap { $0.gjenopprett(i: context) }
            Varsler.planleggAvtale(a)
            resultat.lagtTil += 1
        }

        let finnesProsjekt = Set(try context.fetch(FetchDescriptor<Prosjekt>()).map(\.uuid))
        for k in prosjekter ?? [] {
            guard !finnesProsjekt.contains(k.uuid) else { resultat.hoppetOver += 1; continue }
            let p = Prosjekt(navn: k.navn)
            p.uuid = k.uuid
            p.kundeUUID = k.kundeUUID
            p.kundeNavn = k.kundeNavn
            p.erFastpris = k.erFastpris
            p.timepris = k.timepris
            p.fastpris = k.fastpris
            p.ferdig = k.ferdig
            p.opprettet = k.opprettet
            p.notat = k.notat
            context.insert(p)
            var nye: [Timeforing] = []
            for tk in k.foringer {
                let t = Timeforing(dato: tk.dato, timer: tk.timer, notat: tk.notat)
                t.uuid = tk.uuid
                t.fakturaUUID = tk.fakturaUUID
                context.insert(t)
                nye.append(t)
            }
            p.foringer = nye
            resultat.lagtTil += 1
        }

        // Firmaopplysninger hentes inn hvis de ikke er fylt ut her. Organisasjonsnummeret har en standardverdi,
        // så det er kontonummeret som viser om opplysningene er fylt ut.
        let d = UserDefaults.standard
        if let inn = innstillinger, Fakturering.siffer(d.string(forKey: Firma.kontonr) ?? "").isEmpty,
           let orgnr = inn.firmaOrgnr, !orgnr.isEmpty {
            d.set(inn.firmaNavn, forKey: Firma.navn)
            d.set(inn.firmaEier, forKey: Firma.eier)
            d.set(inn.firmaAdresse, forKey: Firma.adresse)
            d.set(orgnr, forKey: Firma.orgnr)
            d.set(inn.firmaKontonr, forKey: Firma.kontonr)
            d.set(inn.firmaEpost, forKey: Firma.epost)
            if let frist = inn.betalingsfrist { d.set(frist, forKey: Firma.betalingsfrist) }
            if let start = inn.startnummer { d.set(start, forKey: Firma.startnummer) }
            if let takk = inn.takketekst { d.set(takk, forKey: Firma.takketekst) }
        }

        // Innstillinger hentes bare inn hvis lønnen ikke er fylt ut (typisk på en ny telefon).
        if let inn = innstillinger, d.double(forKey: Innstilling.lonn) == 0 {
            d.set(inn.lonn, forKey: Innstilling.lonn)
            d.set(inn.mvaRegistrert, forKey: Innstilling.mvaRegistrert)
            d.set(inn.mvaAarstermin, forKey: Innstilling.mvaAarstermin)
            d.set(inn.forskuddsskatt, forKey: Innstilling.forskuddsskatt)
            d.set(inn.hjemmekontor, forKey: Innstilling.hjemmekontor)
            if let fra = inn.mvaFra { d.set(fra, forKey: Innstilling.mvaFra) }
        }

        try context.save()
        return resultat
    }
}

/// Gjør sikkerhetskopien til en fil som kan lagres med «Arkiver i Filer».
struct SikkerhetskopiFil: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Seksjonen i Innstillinger for iCloud og sikkerhetskopi.
struct SikkerhetskopiSeksjon: View {
    @Environment(\.modelContext) private var context
    @AppStorage("sikkerhetskopi.sist") private var sistKopiert: Double = 0
    @AppStorage(AutoKopi.paaNokkel) private var autoPaa = true
    @AppStorage(AutoKopi.sistNokkel) private var autoSist: Double = 0
    @AppStorage(AutoKopi.stedNokkel) private var autoSted = ""

    @State private var fil: SikkerhetskopiFil?
    @State private var visEksport = false
    @State private var visImport = false
    @State private var melding: String?
    @State private var jobber = false

    private var filnavn: String {
        "Regnskap sikkerhetskopi \(Date.now.formatted(.iso8601.year().month().day()))"
    }

    var body: some View {
        Section {
            HStack {
                Label("iCloud-synk", systemImage: "icloud")
                Spacer()
                if Lagring.brukerICloud && Lagring.iCloudKontoFinnes {
                    Text("På").foregroundStyle(.green)
                } else if !Lagring.iCloudKontoFinnes {
                    Text("Ikke logget inn").foregroundStyle(.orange)
                } else {
                    Text("Av").foregroundStyle(.orange)
                }
            }

            Toggle(isOn: $autoPaa) {
                Label("Automatisk kopi hver dag", systemImage: "clock.arrow.circlepath")
            }
            .onChange(of: autoPaa) { _, paa in
                if paa { AutoKopi.kjorHvisNodvendig(context) }
            }

            Button {
                lagKopi()
            } label: {
                HStack {
                    Label("Lag sikkerhetskopi nå", systemImage: "externaldrive.badge.icloud")
                    if jobber {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(jobber)

            Button {
                visImport = true
            } label: {
                Label("Gjenopprett fra sikkerhetskopi", systemImage: "arrow.counterclockwise.icloud")
            }
            .disabled(jobber)
        } header: {
            Text("Sikkerhetskopi")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if Lagring.brukerICloud {
                    Text("Alt du legger inn, også bilder, synkroniseres automatisk til din private iCloud og kommer tilbake hvis du sletter appen eller bytter telefon.")
                } else {
                    Text("iCloud-synk er ikke slått på i denne versjonen av appen. Ta sikkerhetskopi jevnlig.")
                }
                Text("Synken speiler alt, også det du sletter ved et uhell. Sikkerhetskopien er en egen fil med alt innhold som du kan hente tilbake fra. Gjenoppretting legger bare til det som mangler, og sletter eller endrer aldri noe.")
                if autoPaa {
                    Text("Den automatiske kopien tas når du åpner appen, høyst én gang i døgnet. De fem nyeste og én fra hver av de seks siste månedene med kopi beholdes.")
                }
                if autoSist > 0 {
                    Text("Siste automatiske kopi: \(Date(timeIntervalSince1970: autoSist).formatted(date: .abbreviated, time: .shortened)), \(autoSted)")
                }
                if sistKopiert > 0 {
                    Text("Siste kopi du lagret selv: \(Date(timeIntervalSince1970: sistKopiert).formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
        .fileExporter(isPresented: $visEksport, document: fil, contentType: .json, defaultFilename: filnavn) { resultat in
            switch resultat {
            case .success:
                sistKopiert = Date.now.timeIntervalSince1970
                melding = "Sikkerhetskopien er lagret."
            case .failure(let feil):
                melding = "Kunne ikke lagre: \(feil.localizedDescription)"
            }
            fil = nil
        }
        .fileImporter(isPresented: $visImport, allowedContentTypes: [.json]) { resultat in
            switch resultat {
            case .success(let url):
                gjenopprett(fra: url)
            case .failure(let feil):
                melding = "Kunne ikke åpne filen: \(feil.localizedDescription)"
            }
        }
        .alert("Sikkerhetskopi", isPresented: Binding(get: { melding != nil }, set: { if !$0 { melding = nil } })) {
            Button("OK") { melding = nil }
        } message: {
            Text(melding ?? "")
        }
    }

    private func lagKopi() {
        jobber = true
        defer { jobber = false }
        do {
            let data = try Sikkerhetskopi.lag(fra: context).somData()
            fil = SikkerhetskopiFil(data: data)
            visEksport = true
        } catch {
            melding = "Kunne ikke lage sikkerhetskopi: \(error.localizedDescription)"
        }
    }

    private func gjenopprett(fra url: URL) {
        jobber = true
        defer { jobber = false }
        let tilgang = url.startAccessingSecurityScopedResource()
        defer { if tilgang { url.stopAccessingSecurityScopedResource() } }
        do {
            let kopi = try Sikkerhetskopi.les(Data(contentsOf: url))
            let r = try kopi.gjenopprett(til: context)
            melding = r.lagtTil == 0
                ? "Alt i sikkerhetskopien finnes allerede i appen. Ingenting ble endret."
                : "Hentet tilbake \(r.lagtTil) oppføringer. \(r.hoppetOver) fantes fra før og ble ikke rørt."
        } catch {
            melding = "Kunne ikke lese sikkerhetskopien: \(error.localizedDescription)"
        }
    }
}
