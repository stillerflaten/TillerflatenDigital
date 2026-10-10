import Foundation
import SwiftData
import Testing
@testable import Regnskap

@MainActor
struct SikkerhetskopiTests {
    private func nyDatabase() throws -> ModelContext {
        let konfig = ModelConfiguration(schema: Lagring.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: Lagring.schema, configurations: konfig))
    }

    @Test func kopiTilNyTelefonGirSammeInnhold() throws {
        let gammel = try nyDatabase()
        let bilag = Bilag(tittel: "MacBook-lader", belop: 899, kategori: .utstyr)
        gammel.insert(bilag)
        let side1 = Vedlegg(data: Data([1, 2, 3]), nr: 0)
        let side2 = Vedlegg(data: Data([4, 5, 6]), nr: 1)
        gammel.insert(side1)
        gammel.insert(side2)
        bilag.vedlegg = [side1, side2]
        gammel.insert(Inntekt(belop: 1_234))
        try gammel.save()

        let data = try Sikkerhetskopi.lag(fra: gammel).somData()

        let ny = try nyDatabase()
        let resultat = try Sikkerhetskopi.les(data).gjenopprett(til: ny)
        #expect(resultat.lagtTil == 2)

        let hentet = try ny.fetch(FetchDescriptor<Bilag>())
        #expect(hentet.count == 1)
        #expect(hentet.first?.tittel == "MacBook-lader")
        #expect(hentet.first?.sorterteVedlegg.map(\.data) == [Data([1, 2, 3]), Data([4, 5, 6])])
        #expect(try ny.fetch(FetchDescriptor<Inntekt>()).first?.belop == 1_234)

        // Gjenoppretter du samme kopi en gang til, blir ingenting dobbelt.
        let igjen = try Sikkerhetskopi.les(data).gjenopprett(til: ny)
        #expect(igjen.lagtTil == 0)
        #expect(try ny.fetch(FetchDescriptor<Bilag>()).count == 1)
    }

    @Test func betaltFakturaBlirInntektOgKanAngres() throws {
        let db = try nyDatabase()
        let f = Faktura()
        db.insert(f)
        let linje = FakturaLinje(nr: 1, beskrivelse: "Nettside", antall: 1, enhetspris: 8_000)
        db.insert(linje)
        f.linjer = [linje]
        f.nummer = 1
        f.status = .sendt

        Fakturering.registrerBetalt(f, dato: .now, context: db)
        #expect(f.status == .betalt)
        #expect(try db.fetch(FetchDescriptor<Inntekt>()).map(\.belop) == [8_000])

        Fakturering.angreBetalt(f, context: db)
        #expect(f.status == .sendt)
        #expect(try db.fetch(FetchDescriptor<Inntekt>()).isEmpty)
    }

    @Test func fakturaerKommerMedISikkerhetskopien() throws {
        let gammel = try nyDatabase()
        gammel.insert(Kunde(navn: "Kafé Fjord"))
        let f = Faktura()
        f.nummer = 7
        f.status = .sendt
        f.kundeNavn = "Kafé Fjord"
        gammel.insert(f)
        let linje = FakturaLinje(nr: 1, beskrivelse: "Logo", antall: 1, enhetspris: 2_500)
        gammel.insert(linje)
        f.linjer = [linje]
        try gammel.save()

        let data = try Sikkerhetskopi.lag(fra: gammel).somData()
        let ny = try nyDatabase()
        _ = try Sikkerhetskopi.les(data).gjenopprett(til: ny)

        let hentet = try ny.fetch(FetchDescriptor<Faktura>())
        #expect(hentet.first?.nummer == 7)
        #expect(hentet.first?.total == 2_500)
        #expect(try ny.fetch(FetchDescriptor<Kunde>()).first?.navn == "Kafé Fjord")
    }
}
