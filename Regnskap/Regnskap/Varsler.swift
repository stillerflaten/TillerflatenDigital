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
