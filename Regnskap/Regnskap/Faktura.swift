import Foundation
import SwiftData

/// En kunde du sender faktura til.
@Model
final class Kunde {
    var uuid: UUID = UUID()
    var navn: String = ""
    /// Gateadresse, postnummer og sted, på flere linjer.
    var adresse: String = ""
    /// Organisasjonsnummer hvis kunden er en bedrift.
    var orgnr: String = ""
    var epost: String = ""
    var opprettet: Date = Date.now

    init(navn: String = "") {
        self.navn = navn
    }
}

/// En faktura. Den er et utkast til den ferdigstilles. Da får den nummer,
/// og opplysningene om deg og kunden låses, slik at fakturaen alltid ser lik ut.
@Model
final class Faktura {
    var uuid: UUID = UUID()
    /// Fakturanummer. 0 betyr utkast (ikke nummerert ennå).
    var nummer: Int = 0
    var statusRaw: String = Fakturastatus.utkast.rawValue

    var fakturadato: Date = Date.now
    var forfallsdato: Date = Date.now
    /// Når arbeidet ble levert. Skal stå på fakturaen.
    var leveringsdato: Date = Date.now
    var betaltDato: Date? = nil

    /// 0 hvis du ikke er mva-registrert, ellers 0.25.
    var mvaSats: Double = 0
    /// Tekst nederst på fakturaen, f.eks. «Takk for oppdraget!».
    var merknad: String = ""

    // Kunden, kopiert inn når kunden velges og låst ved ferdigstilling.
    var kundeUUID: UUID? = nil
    var kundeNavn: String = ""
    var kundeAdresse: String = ""
    var kundeOrgnr: String = ""
    var kundeEpost: String = ""

    // Deg, kopiert fra Firmaopplysninger ved ferdigstilling.
    var selgerNavn: String = ""
    var selgerEier: String = ""
    var selgerAdresse: String = ""
    var selgerOrgnr: String = ""
    var selgerKontonr: String = ""
    var selgerEpost: String = ""

    /// Inntekten som ble lagt inn da fakturaen ble betalt.
    var inntektUUID: UUID? = nil

    @Relationship(deleteRule: .cascade, inverse: \FakturaLinje.faktura) var linjer: [FakturaLinje]? = []

    init() {}

    var status: Fakturastatus {
        get { Fakturastatus(rawValue: statusRaw) ?? .utkast }
        set { statusRaw = newValue.rawValue }
    }

    var sorterteLinjer: [FakturaLinje] {
        (linjer ?? []).sorted { $0.nr < $1.nr }
    }

    var sumEksMva: Double { Fakturering.rund(sorterteLinjer.reduce(0) { $0 + $1.belop }) }
    var mvaBelop: Double { Fakturering.rund(sumEksMva * mvaSats) }
    var total: Double { sumEksMva + mvaBelop }

    var erForfalt: Bool {
        status == .sendt && Frister.kalender.startOfDay(for: forfallsdato) < Frister.kalender.startOfDay(for: .now)
    }

    var tittel: String {
        let kunde = kundeNavn.isEmpty ? "Uten kunde" : kundeNavn
        return nummer > 0 ? "Faktura \(nummer) – \(kunde)" : "Utkast – \(kunde)"
    }
}

/// Én linje på fakturaen: hva du har levert.
@Model
final class FakturaLinje {
    var uuid: UUID = UUID()
    var nr: Int = 0
    var beskrivelse: String = ""
    var antall: Double = 1
    var enhetspris: Double = 0
    var faktura: Faktura?

    init(nr: Int = 0, beskrivelse: String = "", antall: Double = 1, enhetspris: Double = 0) {
        self.nr = nr
        self.beskrivelse = beskrivelse
        self.antall = antall
        self.enhetspris = enhetspris
    }

    var belop: Double { Fakturering.rund(antall * enhetspris) }
}

enum Fakturastatus: String, CaseIterable {
    case utkast, sendt, betalt

    var navn: String {
        switch self {
        case .utkast: "Utkast"
        case .sendt: "Sendt"
        case .betalt: "Betalt"
        }
    }
}

/// Opplysningene om foretaket som skal stå på fakturaen.
enum Firma {
    static let navn = "firma.navn"
    static let eier = "firma.eier"
    static let adresse = "firma.adresse"
    static let orgnr = "firma.orgnr"
    static let kontonr = "firma.kontonr"
    static let epost = "firma.epost"
    static let betalingsfrist = "firma.betalingsfrist"
    static let startnummer = "faktura.startnummer"

    static let standardNavn = "Tillerflaten Digital"
    static let standardEpost = "post@tillerflatendigital.no"

    private static var d: UserDefaults { .standard }

    static var lagretNavn: String { d.string(forKey: navn) ?? standardNavn }
    static var lagretEpost: String { d.string(forKey: epost) ?? standardEpost }
    static var lagretBetalingsfrist: Int { d.object(forKey: betalingsfrist) as? Int ?? 14 }
    static var lagretStartnummer: Int { d.object(forKey: startnummer) as? Int ?? 1 }

    /// Det som mangler før du kan sende en faktura.
    static var mangler: [String] {
        var liste: [String] = []
        if lagretNavn.trimmet.isEmpty { liste.append("navn på foretaket") }
        if (d.string(forKey: eier) ?? "").trimmet.isEmpty { liste.append("navnet ditt") }
        if (d.string(forKey: adresse) ?? "").trimmet.isEmpty { liste.append("adresse") }
        if Fakturering.siffer(d.string(forKey: orgnr) ?? "").count != 9 { liste.append("organisasjonsnummer") }
        if Fakturering.siffer(d.string(forKey: kontonr) ?? "").count != 11 { liste.append("kontonummer") }
        return liste
    }
}

enum Fakturering {
    /// Neste ledige fakturanummer. Nummerene skal komme i rekkefølge uten hull.
    static func nesteNummer(brukte: [Int], startnummer: Int) -> Int {
        max(startnummer, (brukte.max() ?? 0) + 1)
    }

    @MainActor
    static func nesteNummer(_ context: ModelContext) -> Int {
        let alle = (try? context.fetch(FetchDescriptor<Faktura>())) ?? []
        return nesteNummer(brukte: alle.map(\.nummer).filter { $0 > 0 }, startnummer: Firma.lagretStartnummer)
    }

    /// Hva som mangler på selve fakturaen før den kan ferdigstilles.
    static func mangler(i faktura: Faktura) -> [String] {
        var liste = Firma.mangler.map { "Firmaopplysninger: \($0)" }
        if faktura.kundeNavn.trimmet.isEmpty { liste.append("Velg en kunde") }
        else if faktura.kundeAdresse.trimmet.isEmpty { liste.append("Kunden mangler adresse") }
        if faktura.sorterteLinjer.isEmpty || faktura.sumEksMva <= 0 { liste.append("Legg inn minst én linje med beløp") }
        if faktura.sorterteLinjer.contains(where: { $0.beskrivelse.trimmet.isEmpty }) {
            liste.append("Alle linjer må ha en beskrivelse")
        }
        return liste
    }

    /// Gir fakturaen nummer og låser opplysningene om deg og kunden.
    @MainActor
    static func ferdigstill(_ faktura: Faktura, kunde: Kunde?, mvaRegistrert: Bool, context: ModelContext) {
        guard faktura.status == .utkast else { return }
        if let kunde {
            kopier(kunde, til: faktura)
        }
        let d = UserDefaults.standard
        faktura.selgerNavn = Firma.lagretNavn
        faktura.selgerEier = d.string(forKey: Firma.eier) ?? ""
        faktura.selgerAdresse = d.string(forKey: Firma.adresse) ?? ""
        faktura.selgerOrgnr = d.string(forKey: Firma.orgnr) ?? ""
        faktura.selgerKontonr = d.string(forKey: Firma.kontonr) ?? ""
        faktura.selgerEpost = Firma.lagretEpost
        faktura.mvaSats = mvaRegistrert ? 0.25 : 0
        faktura.nummer = nesteNummer(context)
        faktura.status = .sendt
        try? context.save()
    }

    static func kopier(_ kunde: Kunde, til faktura: Faktura) {
        faktura.kundeUUID = kunde.uuid
        faktura.kundeNavn = kunde.navn
        faktura.kundeAdresse = kunde.adresse
        faktura.kundeOrgnr = kunde.orgnr
        faktura.kundeEpost = kunde.epost
    }

    /// Markerer fakturaen som betalt og legger beløpet inn som inntekt.
    @MainActor
    static func registrerBetalt(_ faktura: Faktura, dato: Date, context: ModelContext) {
        guard faktura.status == .sendt else { return }
        let inntekt = Inntekt(dato: dato, belop: faktura.sumEksMva, kilde: "Faktura")
        inntekt.notat = "Faktura \(faktura.nummer) – \(faktura.kundeNavn)"
            + (faktura.mvaBelop > 0 ? ". Kunden betalte \(faktura.total.kr) inkl. \(faktura.mvaBelop.kr) i mva." : "")
        context.insert(inntekt)
        faktura.inntektUUID = inntekt.uuid
        faktura.betaltDato = dato
        faktura.status = .betalt
        try? context.save()
    }

    /// Angrer betalingen og fjerner inntekten som ble lagt inn.
    @MainActor
    static func angreBetalt(_ faktura: Faktura, context: ModelContext) {
        guard faktura.status == .betalt else { return }
        if let id = faktura.inntektUUID {
            let beskrivelse = FetchDescriptor<Inntekt>(predicate: #Predicate<Inntekt> { $0.uuid == id })
            for inntekt in (try? context.fetch(beskrivelse)) ?? [] {
                context.delete(inntekt)
            }
        }
        faktura.inntektUUID = nil
        faktura.betaltDato = nil
        faktura.status = .sendt
        try? context.save()
    }

    static func rund(_ verdi: Double) -> Double {
        (verdi * 100).rounded() / 100
    }

    static func siffer(_ tekst: String) -> String {
        tekst.filter(\.isNumber)
    }

    /// 1234 56 78901
    static func kontonr(_ tekst: String) -> String {
        let s = Array(siffer(tekst))
        guard s.count == 11 else { return tekst }
        return "\(String(s[0..<4])) \(String(s[4..<6])) \(String(s[6..<11]))"
    }

    /// 123 456 789
    static func orgnr(_ tekst: String) -> String {
        let s = Array(siffer(tekst))
        guard s.count == 9 else { return tekst }
        return "\(String(s[0..<3])) \(String(s[3..<6])) \(String(s[6..<9]))"
    }

    /// Kronebeløp med øre: 12 345,00 kr
    static func kroner(_ verdi: Double) -> String {
        verdi.formatted(.currency(code: "NOK").precision(.fractionLength(2)).locale(Locale(identifier: "nb_NO")))
    }

    static func antall(_ verdi: Double) -> String {
        verdi.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "nb_NO")))
    }
}

extension String {
    var trimmet: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
