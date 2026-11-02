import Foundation
import UserNotifications

/// Lokale påminnelser om frister og ubetalte regninger.
enum Varsler {
    static func beOmTillatelse() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Fjerner gamle fristvarsler og legger inn nye for alle kommende frister.
    static func planleggFrister(_ frister: [Frist], dagerFor: Int) {
        let senter = UNUserNotificationCenter.current()
        senter.getPendingNotificationRequests { ventende in
            let gamle = ventende.map(\.identifier).filter { $0.hasPrefix("frist-") }
            senter.removePendingNotificationRequests(withIdentifiers: gamle)

            for frist in frister {
                let innhold = UNMutableNotificationContent()
                innhold.title = frist.tittel
                innhold.body = dagerFor == 0
                    ? "Fristen er i dag. \(frist.forklaring)"
                    : "Fristen er om \(dagerFor) dager. \(frist.forklaring)"
                innhold.sound = .default
                leggTil(id: "frist-\(frist.id)", dato: frist.dato, dagerFor: dagerFor, innhold: innhold)
            }
        }
    }

    static func planleggRegning(_ bilag: Bilag) {
        let id = "regning-\(bilag.uuid.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        guard bilag.erRegning, !bilag.erBetalt, let forfall = bilag.forfallsdato else { return }
        let innhold = UNMutableNotificationContent()
        innhold.title = "Regning forfaller i morgen"
        innhold.body = "\(bilag.tittel.isEmpty ? "Regning" : bilag.tittel): \(bilag.belop.kr)"
        innhold.sound = .default
        leggTil(id: id, dato: forfall, dagerFor: 1, innhold: innhold)
    }

    static func fjernRegning(_ bilag: Bilag) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["regning-\(bilag.uuid.uuidString)"])
    }

    /// Varsel dagen etter forfall hvis kunden ikke har betalt.
    static func planleggFaktura(_ faktura: Faktura) {
        let id = "faktura-\(faktura.uuid.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        guard faktura.status == .sendt, !faktura.erKreditnota else { return }
        let innhold = UNMutableNotificationContent()
        innhold.title = "Faktura \(faktura.nummer) er ikke betalt"
        innhold.body = "\(faktura.kundeNavn) skulle betalt \(faktura.total.kr) i går. Har pengene kommet, merker du fakturaen som betalt. Hvis ikke, kan du sende en purring fra fakturaen."
        innhold.sound = .default
        leggTil(id: id, dato: faktura.gjeldendeFrist, dagerFor: -1, innhold: innhold)
    }

    static func fjernFaktura(_ faktura: Faktura) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["faktura-\(faktura.uuid.uuidString)"])
    }

    /// Påminnelse om å legge inn kvitteringen samme dag som en fast utgift trekkes.
    static func planleggFastUtgift(_ utgift: FastUtgift) {
        let id = "fast-\(utgift.uuid.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        guard utgift.aktiv else { return }
        let innhold = UNMutableNotificationContent()
        innhold.title = "Husk kvitteringen: \(utgift.navn)"
        innhold.body = "\(utgift.belop.kr) trekkes i dag. Legg inn kvitteringen i Regnskap mens du husker det."
        innhold.sound = .default
        leggTil(id: id, dato: utgift.nesteTrekk, dagerFor: 0, innhold: innhold)
    }

    static func fjernFastUtgift(_ utgift: FastUtgift) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["fast-\(utgift.uuid.uuidString)"])
    }

    /// Påminnelse om å fakturere en fast avtale den dagen fakturaen skal lages.
    static func planleggAvtale(_ avtale: Avtale) {
        let id = "avtale-\(avtale.uuid.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        guard avtale.aktiv else { return }
        let innhold = UNMutableNotificationContent()
        innhold.title = "Tid for å fakturere: \(avtale.navn)"
        innhold.body = "\(avtale.kundeNavn.isEmpty ? "" : avtale.kundeNavn + ", ")\(avtale.belop.kr) for \(Avtaler.periodetekst(fra: avtale.nestePeriodeFra, til: avtale.nestePeriodeTil)). Åpne Inntekter → Avtaler for å lage fakturautkastet."
        innhold.sound = .default
        leggTil(id: id, dato: avtale.nesteFakturadato, dagerFor: 0, innhold: innhold)
    }

    static func fjernAvtale(_ avtale: Avtale) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["avtale-\(avtale.uuid.uuidString)"])
    }

    /// Varsel `dagerFor` dager før et huskepunkt, og et til på selve dagen.
    static func planleggHuskepunkt(_ h: Huskepunkt) {
        let id = "husk-\(h.uuid.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id, id + "-dagen"])
        guard !h.ferdig else { return }
        let notat = h.notat.trimmingCharacters(in: .whitespacesAndNewlines)

        let paaDagen = UNMutableNotificationContent()
        paaDagen.title = h.tittel
        paaDagen.body = notat.isEmpty ? "I dag er dagen." : "I dag er dagen. \(notat)"
        paaDagen.sound = .default
        leggTil(id: h.dagerFor == 0 ? id : id + "-dagen", dato: h.dato, dagerFor: 0, innhold: paaDagen)

        guard h.dagerFor > 0 else { return }
        let dato = h.dato.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "nb_NO")))
        let innhold = UNMutableNotificationContent()
        innhold.title = h.tittel
        innhold.body = "Om \(Huskepunkter.varseltekst(h.dagerFor).replacingOccurrences(of: " før", with: "")) (\(dato))."
            + (notat.isEmpty ? "" : " \(notat)")
        innhold.sound = .default
        leggTil(id: id, dato: h.dato, dagerFor: h.dagerFor, innhold: innhold)
    }

    static func fjernHuskepunkt(_ h: Huskepunkt) {
        let id = "husk-\(h.uuid.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id, id + "-dagen"])
    }

    /// Legger inn varsler for alle huskepunktene på nytt, og fjerner varsler for huskepunkter som er slettet.
    static func planleggHuskepunkter(_ alle: [Huskepunkt]) {
        let finnes = Set(alle.map { "husk-\($0.uuid.uuidString)" })
        let senter = UNUserNotificationCenter.current()
        senter.getPendingNotificationRequests { ventende in
            let gamle = ventende.map(\.identifier).filter {
                $0.hasPrefix("husk-") && !finnes.contains($0.replacingOccurrences(of: "-dagen", with: ""))
            }
            senter.removePendingNotificationRequests(withIdentifiers: gamle)
        }
        for h in alle { planleggHuskepunkt(h) }
    }

    static func fjernAlleFrister() {
        let senter = UNUserNotificationCenter.current()
        senter.getPendingNotificationRequests { ventende in
            senter.removePendingNotificationRequests(
                withIdentifiers: ventende.map(\.identifier).filter { $0.hasPrefix("frist-") })
        }
    }

    private static func leggTil(id: String, dato: Date, dagerFor: Int, innhold: UNNotificationContent) {
        let cal = Frister.kalender
        guard let dag = cal.date(byAdding: .day, value: -dagerFor, to: cal.startOfDay(for: dato)),
              let tidspunkt = cal.date(bySettingHour: 9, minute: 0, second: 0, of: dag),
              tidspunkt > .now else { return }
        var komponenter = cal.dateComponents([.year, .month, .day, .hour, .minute], from: tidspunkt)
        komponenter.timeZone = cal.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: komponenter, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: innhold, trigger: trigger))
    }
}
