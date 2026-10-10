import Foundation
import SwiftData

/// Hvor dataene lagres: i appen på telefonen, og synkronisert til din private iCloud.
enum Lagring {
    /// Må være lik containeren under Signing & Capabilities → iCloud i Xcode.
    static let iCloudContainer = "iCloud.Silje.Regnskap"

    static let schema = Schema([Bilag.self, Vedlegg.self, Inntekt.self, Driftsmiddel.self, Kjoretur.self,
                                     Kunde.self, Faktura.self, FakturaLinje.self])

    /// Om appen fikk koblet seg til iCloud ved oppstart.
    private(set) static var brukerICloud = false

    /// Er du logget inn på iCloud på denne enheten?
    static var iCloudKontoFinnes: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    static func lagContainer() -> ModelContainer {
        // Prøv iCloud-synk først. Hvis iCloud ikke er satt opp i Xcode ennå,
        // lagres alt lokalt i samme fil, så ingenting forsvinner.
        do {
            let konfig = ModelConfiguration(schema: schema, cloudKitDatabase: .private(iCloudContainer))
            let container = try ModelContainer(for: schema, configurations: konfig)
            brukerICloud = true
            return container
        } catch {
            print("iCloud-synk er ikke tilgjengelig, lagrer lokalt: \(error)")
        }
        do {
            let konfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: konfig)
        } catch {
            fatalError("Klarte ikke å åpne databasen: \(error)")
        }
    }

    /// Flytter bilder fra første versjon (ett bilde per bilag) over til vedlegg.
    @MainActor
    static func flyttGamleBilder(_ context: ModelContext) {
        guard let alle = try? context.fetch(FetchDescriptor<Bilag>()) else { return }
        var endret = false
        for bilag in alle {
            guard let data = bilag.bilde else { continue }
            let vedlegg = Vedlegg(data: data)
            vedlegg.opprettet = bilag.dato
            context.insert(vedlegg)
            bilag.vedlegg = (bilag.vedlegg ?? []) + [vedlegg]
            bilag.bilde = nil
            endret = true
        }
        if endret { try? context.save() }
    }
}
