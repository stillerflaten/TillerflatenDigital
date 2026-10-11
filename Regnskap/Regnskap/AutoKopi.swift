import Foundation
import SwiftData

/// Tar en sikkerhetskopi automatisk én gang i døgnet, når appen åpnes.
///
/// iCloud-synken speiler alt mellom enhetene, også det du sletter ved et uhell.
/// Disse filene ligger utenfor databasen, så de kan hentes tilbake med
/// «Gjenopprett fra sikkerhetskopi» selv om noe forsvinner fra appen.
enum AutoKopi {
    static let paaNokkel = "autokopi.paa"
    static let sistNokkel = "autokopi.sist"
    static let stedNokkel = "autokopi.sted"

    static let mappenavn = "Sikkerhetskopier"
    static let filprefiks = "Regnskap "

    /// Så mange av de nyeste kopiene beholdes.
    static let antallNyeste = 5
    /// I tillegg beholdes den nyeste kopien fra hver av så mange måneder.
    static let antallMaaneder = 6

    static var erPaa: Bool {
        UserDefaults.standard.object(forKey: paaNokkel) as? Bool ?? true
    }

    @MainActor private static var kjorer = false

    /// Lager en kopi hvis det har gått et døgn siden forrige.
    @MainActor
    static func kjorHvisNodvendig(_ context: ModelContext) {
        guard erPaa, !kjorer else { return }
        let sist = UserDefaults.standard.double(forKey: sistNokkel)
        guard Date.now.timeIntervalSince1970 - sist >= 20 * 60 * 60 else { return }
        kjor(context)
    }

    @MainActor
    static func kjor(_ context: ModelContext) {
        guard !kjorer else { return }
        kjorer = true
        let container = context.container
        let navn = filnavn(for: .now)
        // Kopien lages i bakgrunnen, så appen ikke henger mens alle bildene pakkes.
        Task.detached(priority: .utility) {
            let sted = lagKopi(container: container, filnavn: navn)
            await MainActor.run {
                kjorer = false
                if let sted {
                    UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: sistNokkel)
                    UserDefaults.standard.set(sted, forKey: stedNokkel)
                }
            }
        }
    }

    private static func lagKopi(container: ModelContainer, filnavn: String) -> String? {
        let context = ModelContext(container)
        // Ikke ta kopi av en tom app, f.eks. rett etter ny installasjon før iCloud har hentet alt.
        let antall = ((try? context.fetchCount(FetchDescriptor<Bilag>())) ?? 0)
            + ((try? context.fetchCount(FetchDescriptor<Inntekt>())) ?? 0)
            + ((try? context.fetchCount(FetchDescriptor<Faktura>())) ?? 0)
        guard antall > 0 else { return nil }
        guard let data = try? Sikkerhetskopi.lag(fra: context).somData() else { return nil }
        return lagre(data, filnavn: filnavn)
    }

    static func filnavn(for dato: Date) -> String {
        let f = DateFormatter()
        f.calendar = Frister.kalender
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Frister.kalender.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return "\(filprefiks)\(f.string(from: dato)).json"
    }

    /// Mappen i iCloud Drive (Filer › iCloud Drive › Regnskap), eller på enheten hvis iCloud Drive ikke er tilgjengelig.
    /// Kalles ikke fra hovedtråden, fordi iCloud-oppslaget kan ta litt tid.
    private static func mappe() -> (url: URL, sted: String)? {
        let fm = FileManager.default
        if let sky = fm.url(forUbiquityContainerIdentifier: Lagring.iCloudContainer) {
            return (sky.appendingPathComponent("Documents").appendingPathComponent(mappenavn), "iCloud Drive › Regnskap › \(mappenavn)")
        }
        if let lokal = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            return (lokal.appendingPathComponent(mappenavn), "På denne enheten")
        }
        return nil
    }

    /// Skriver filen og rydder bort gamle kopier. Gir tilbake hvor den ble lagret.
    private static func lagre(_ data: Data, filnavn: String) -> String? {
        guard let m = mappe() else { return nil }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: m.url, withIntermediateDirectories: true)
            let url = m.url.appendingPathComponent(filnavn)
            var feil: NSError?
            var skrivefeil: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &feil) { u in
                do { try data.write(to: u, options: .atomic) } catch { skrivefeil = error }
            }
            if let e = feil ?? skrivefeil { throw e }
            ryddOpp(i: m.url)
            return m.sted
        } catch {
            print("Automatisk sikkerhetskopi feilet: \(error)")
            return nil
        }
    }

    private static func ryddOpp(i mappe: URL) {
        let fm = FileManager.default
        guard let innhold = try? fm.contentsOfDirectory(atPath: mappe.path) else { return }
        // Kopier som ikke er lastet ned, kan ligge som «.Navn.json.icloud».
        let filer = innhold.map { n in
            n.hasPrefix(".") && n.hasSuffix(".icloud") ? String(n.dropFirst().dropLast(7)) : n
        }
        for navn in filerSomSkalSlettes(filer) {
            let url = mappe.appendingPathComponent(navn)
            var feil: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &feil) { u in
                try? fm.removeItem(at: u)
            }
        }
    }

    /// Hvilke automatiske kopier som kan slettes. Beholder de nyeste og den nyeste fra hver av de siste månedene.
    /// Filer appen ikke selv har laget, blir aldri rørt.
    static func filerSomSkalSlettes(_ filer: [String]) -> [String] {
        // Navnet er «Regnskap yyyy-MM-dd.json», så alfabetisk rekkefølge er også datorekkefølge.
        let egne = filer
            .filter { $0.hasPrefix(filprefiks) && $0.hasSuffix(".json") && $0.count == filprefiks.count + 15 }
            .sorted(by: >)
        var behold = Set(egne.prefix(antallNyeste))
        var maaneder: [String] = []
        for navn in egne {
            let maaned = String(navn.dropFirst(filprefiks.count).prefix(7))
            if !maaneder.contains(maaned) {
                guard maaneder.count < antallMaaneder else { break }
                maaneder.append(maaned)
                behold.insert(navn)
            }
        }
        return egne.filter { !behold.contains($0) }
    }
}
