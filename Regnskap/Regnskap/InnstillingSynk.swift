import Foundation

/// Synker innstillingene mellom telefon og Mac via iCloud (nøkkel–verdi-lageret).
///
/// Appen leser og skriver fortsatt `UserDefaults` (via `@AppStorage`) som før.
/// Denne typen kopierer bare verdiene fram og tilbake, så resten av koden trenger ikke vite om den.
enum InnstillingSynk {
    /// Innstillinger som skal være like på alle enheter. Varsler, kalender og lås er per enhet.
    static let nokler: [String] = [
        Innstilling.lonn, Innstilling.mvaRegistrert, Innstilling.mvaAarstermin, Innstilling.mvaFra,
        Innstilling.forskuddsskatt, Innstilling.hjemmekontor,
        Firma.navn, Firma.eier, Firma.adresse, Firma.orgnr, Firma.kontonr, Firma.epost,
        Firma.betalingsfrist, Firma.startnummer,
        "sjekkliste.ferdig",
    ]

    private static var observatorer: [NSObjectProtocol] = []
    private static var oppdaterer = false

    /// Kalles én gang når appen starter.
    static func start() {
        guard observatorer.isEmpty else { return }
        let sky = NSUbiquitousKeyValueStore.default
        let lokalt = UserDefaults.standard

        observatorer.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: sky, queue: .main
        ) { varsel in
            let endret = varsel.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? nokler
            hentFraSky(endret.filter(nokler.contains))
        })
        observatorer.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: lokalt, queue: .main
        ) { _ in
            sendTilSky()
        })

        sky.synchronize()
        // Første gang på en ny enhet: det som ligger i iCloud, vinner. Det som bare finnes her, sendes opp.
        hentFraSky(nokler.filter { sky.object(forKey: $0) != nil })
        sendTilSky()
    }

    private static func hentFraSky(_ endret: [String]) {
        let sky = NSUbiquitousKeyValueStore.default
        let lokalt = UserDefaults.standard
        oppdaterer = true
        defer { oppdaterer = false }
        for nokkel in endret {
            let verdi = sky.object(forKey: nokkel)
            if !erLike(verdi, lokalt.object(forKey: nokkel)) {
                lokalt.set(verdi, forKey: nokkel)
            }
        }
    }

    private static func sendTilSky() {
        guard !oppdaterer else { return }
        let sky = NSUbiquitousKeyValueStore.default
        let lokalt = UserDefaults.standard
        for nokkel in nokler {
            guard let verdi = lokalt.object(forKey: nokkel) else { continue }
            if !erLike(verdi, sky.object(forKey: nokkel)) {
                sky.set(verdi, forKey: nokkel)
            }
        }
    }

    static func erLike(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a as NSObject, b as NSObject): a.isEqual(b)
        default: false
        }
    }
}
