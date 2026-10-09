import Foundation
import SwiftData

// Alle felt har standardverdier, så det blir enkelt å skru på iCloud-synk senere.

enum Utgiftskategori: String, CaseIterable, Identifiable, Codable {
    case programvare, utstyr, driftsmiddel, kontor, telefonInternett, kurs, markedsforing, reise, regnskap, annet

    var id: String { rawValue }

    var navn: String {
        switch self {
        case .programvare: "Programvare og abonnement"
        case .utstyr: "Utstyr under 30 000 kr"
        case .driftsmiddel: "Utstyr over 30 000 kr (avskrives)"
        case .kontor: "Kontorrekvisita"
        case .telefonInternett: "Telefon og internett"
        case .kurs: "Kurs og faglitteratur"
        case .markedsforing: "Markedsføring"
        case .reise: "Reise"
        case .regnskap: "Regnskap, bank og gebyrer"
        case .annet: "Annet"
        }
    }

    var ikon: String {
        switch self {
        case .programvare: "app.badge"
        case .utstyr: "laptopcomputer"
        case .driftsmiddel: "desktopcomputer"
        case .kontor: "paperclip"
        case .telefonInternett: "wifi"
        case .kurs: "book"
        case .markedsforing: "megaphone"
        case .reise: "airplane"
        case .regnskap: "building.columns"
        case .annet: "tray"
        }
    }

    var hjelpetekst: String? {
        switch self {
        case .programvare: "F.eks. Apple Developer Program, Claude, GitHub, domene og webhotell."
        case .driftsmiddel: "Trekkes ikke fra med en gang. Legg også utstyret inn under Kalkulatorer → Avskrivning, så regner appen ut årets fradrag."
        case .telefonInternett: "Brukes det også privat? Sett næringsandelen til det du faktisk bruker i foretaket."
        default: nil
        }
    }
}

/// En kvittering eller regning.
@Model
final class Bilag {
    var uuid: UUID = UUID()
    var dato: Date = Date.now
    var tittel: String = ""
    /// Totalbeløp slik det står på kvitteringen (inkl. mva).
    var belop: Double = 0
    /// Mva-beløpet på kvitteringen. Brukes bare hvis du er mva-registrert.
    var mva: Double = 0
    var kategoriRaw: String = Utgiftskategori.annet.rawValue
    /// Prosent (0–100) av utgiften som gjelder foretaket.
    var naeringsandel: Double = 100
    var notat: String = ""

    var erRegning: Bool = false
    var forfallsdato: Date? = nil
    var erBetalt: Bool = true

    @Attribute(.externalStorage) var bilde: Data? = nil

    var kategori: Utgiftskategori {
        get { Utgiftskategori(rawValue: kategoriRaw) ?? .annet }
        set { kategoriRaw = newValue.rawValue }
    }

    /// Beløpet som kan trekkes fra som kostnad i år.
    func fradrag(mvaRegistrert: Bool) -> Double {
        guard kategori != .driftsmiddel else { return 0 }
        let grunnlag = mvaRegistrert ? belop - mva : belop
        return grunnlag * naeringsandel / 100
    }

    init(dato: Date = .now, tittel: String = "", belop: Double = 0, kategori: Utgiftskategori = .annet) {
        self.dato = dato
        self.tittel = tittel
        self.belop = belop
        self.kategoriRaw = kategori.rawValue
    }
}

/// En utbetaling eller annen inntekt.
@Model
final class Inntekt {
    var uuid: UUID = UUID()
    var dato: Date = Date.now
    var belop: Double = 0
    var kilde: String = "App Store"
    var notat: String = ""
    @Attribute(.externalStorage) var bilde: Data? = nil

    init(dato: Date = .now, belop: Double = 0, kilde: String = "App Store") {
        self.dato = dato
        self.belop = belop
        self.kilde = kilde
    }
}

/// Utstyr som avskrives (eller trekkes fra direkte).
@Model
final class Driftsmiddel {
    var uuid: UUID = UUID()
    var navn: String = ""
    var kjopsdato: Date = Date.now
    /// Inkl. mva hvis du ikke er mva-registrert.
    var kostpris: Double = 0
    var gruppeRaw: String = Saldogruppe.a.rawValue
    var naeringsandel: Double = 100
    var levetidMinst3Aar: Bool = true
    var notat: String = ""

    var gruppe: Saldogruppe {
        get { Saldogruppe(rawValue: gruppeRaw) ?? .a }
        set { gruppeRaw = newValue.rawValue }
    }

    var kjopsaar: Int { Frister.kalender.component(.year, from: kjopsdato) }

    func metode(satser: Skattesatser) -> Fradragsmetode {
        Avskrivning.metode(kostpris: kostpris, naeringsandel: naeringsandel / 100,
                           levetidMinst3Aar: levetidMinst3Aar, gruppe: gruppe, satser: satser)
    }

    init(navn: String = "", kjopsdato: Date = .now, kostpris: Double = 0, gruppe: Saldogruppe = .a) {
        self.navn = navn
        self.kjopsdato = kjopsdato
        self.kostpris = kostpris
        self.gruppeRaw = gruppe.rawValue
    }
}

/// Kjøring med egen bil for foretaket.
@Model
final class Kjoretur {
    var uuid: UUID = UUID()
    var dato: Date = Date.now
    var fra: String = ""
    var til: String = ""
    var formal: String = ""
    var km: Double = 0

    init(dato: Date = .now, fra: String = "", til: String = "", formal: String = "", km: Double = 0) {
        self.dato = dato
        self.fra = fra
        self.til = til
        self.formal = formal
        self.km = km
    }
}

extension Date {
    var aar: Int { Frister.kalender.component(.year, from: self) }
}
