import EventKit
import UIKit

/// Legger frister og forfall inn i iPhone-kalenderen, i en egen kalender som heter «Tillerflaten Digital».
/// Hver hendelse merkes med en lenke (tillerflatendigital://…), så samme frist aldri legges inn to ganger.
@MainActor
enum Kalender {
    static let navn = "Tillerflaten Digital"
    private static let store = EKEventStore()
    private static let idNokkel = "kalender.id"

    enum Feil: LocalizedError {
        case ingenTilgang
        var errorDescription: String? {
            "Appen har ikke tilgang til kalenderen. Gå til Innstillinger → Personvern og sikkerhet → Kalendere → Regnskap og velg «Full tilgang»."
        }
    }

    static var harTilgang: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static func beOmTilgang() async -> Bool {
        if harTilgang { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Kalenderen «Tillerflaten Digital». Lages første gang den trengs.
    private static func appKalender() throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: idNokkel), let kalender = store.calendar(withIdentifier: id) {
            return kalender
        }
        if let kalender = store.calendars(for: .event).first(where: { $0.title == navn && $0.allowsContentModifications }) {
            UserDefaults.standard.set(kalender.calendarIdentifier, forKey: idNokkel)
            return kalender
        }
        let kalender = EKCalendar(for: .event, eventStore: store)
        kalender.title = navn
        kalender.cgColor = UIColor(red: 0.12, green: 0.37, blue: 0.42, alpha: 1).cgColor
        // Helst samme konto som standardkalenderen (vanligvis iCloud, så den vises på Mac også).
        let kilder = [store.defaultCalendarForNewEvents?.source,
                      store.sources.first(where: { $0.sourceType == .calDAV }),
                      store.sources.first(where: { $0.sourceType == .local })].compactMap { $0 }
        var sisteFeil: Error?
        for kilde in kilder {
            kalender.source = kilde
            do {
                try store.saveCalendar(kalender, commit: true)
                UserDefaults.standard.set(kalender.calendarIdentifier, forKey: idNokkel)
                return kalender
            } catch {
                sisteFeil = error
            }
        }
        throw sisteFeil ?? Feil.ingenTilgang
    }

    private static func lenke(for id: String) -> URL {
        URL(string: "tillerflatendigital://\(id)")!
    }

    private static func finn(id: String, rundt dato: Date, i kalender: EKCalendar) -> EKEvent? {
        let cal = Frister.kalender
        let start = cal.date(byAdding: .day, value: -400, to: dato) ?? dato
        let slutt = cal.date(byAdding: .day, value: 400, to: dato) ?? dato
        let sok = store.predicateForEvents(withStart: start, end: slutt, calendars: [kalender])
        return store.events(matching: sok).first { $0.url == lenke(for: id) }
    }

    /// Legger inn (eller oppdaterer) en heldagshendelse med varsel kl. 09.00 `dagerFor` dager før.
    static func leggInn(id: String, tittel: String, notat: String, dato: Date, dagerFor: Int) throws {
        guard harTilgang else { throw Feil.ingenTilgang }
        let kalender = try appKalender()
        let hendelse = finn(id: id, rundt: dato, i: kalender) ?? EKEvent(eventStore: store)
        hendelse.calendar = kalender
        hendelse.title = tittel
        hendelse.notes = notat
        hendelse.url = lenke(for: id)
        hendelse.isAllDay = true
        hendelse.startDate = Frister.kalender.startOfDay(for: dato)
        hendelse.endDate = hendelse.startDate
        hendelse.alarms = [EKAlarm(relativeOffset: TimeInterval(-dagerFor * 86_400 + 9 * 3_600))]
        try store.save(hendelse, span: .thisEvent, commit: true)
    }

    static func fjern(id: String, rundt dato: Date) throws {
        guard harTilgang else { return }
        let kalender = try appKalender()
        if let hendelse = finn(id: id, rundt: dato, i: kalender) {
            try store.remove(hendelse, span: .thisEvent, commit: true)
        }
    }

    /// Id-ene til alt appen har lagt inn i kalenderen i perioden.
    static func lagtInn(fra start: Date, til slutt: Date) -> Set<String> {
        guard harTilgang, let kalender = try? appKalender() else { return [] }
        let sok = store.predicateForEvents(withStart: start, end: slutt, calendars: [kalender])
        return Set(store.events(matching: sok).compactMap { $0.url?.absoluteString.replacingOccurrences(of: "tillerflatendigital://", with: "") })
    }

    // MARK: Snarveier

    static func leggInn(_ frist: Frist, dagerFor: Int) throws {
        try leggInn(id: "frist-\(frist.id)", tittel: frist.tittel, notat: frist.forklaring, dato: frist.dato, dagerFor: dagerFor)
    }

    static func leggInn(regning: Bilag) throws {
        guard let forfall = regning.forfallsdato else { return }
        let tittel = "Betal: \(regning.tittel.isEmpty ? "regning" : regning.tittel)"
        try leggInn(id: "regning-\(regning.uuid.uuidString)", tittel: tittel,
                    notat: "Beløp: \(regning.belop.kr)\n\(regning.notat)", dato: forfall, dagerFor: 1)
    }

    static func fjern(regning: Bilag) {
        guard let forfall = regning.forfallsdato else { return }
        try? fjern(id: "regning-\(regning.uuid.uuidString)", rundt: forfall)
    }
}
