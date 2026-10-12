import Foundation
import SwiftData
import UIKit
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

    private func sendtFaktura(_ db: ModelContext, belop: Double) -> Faktura {
        let f = Faktura()
        db.insert(f)
        let linje = FakturaLinje(nr: 1, beskrivelse: "Nettside", antall: 1, enhetspris: belop)
        db.insert(linje)
        f.linjer = [linje]
        f.nummer = Fakturering.nesteNummer(db)
        f.status = .sendt
        return f
    }

    @Test func helKreditnotaPaaUbetaltFakturaAvslutterDen() throws {
        let db = try nyDatabase()
        let f = sendtFaktura(db, belop: 5_000)
        let k = Fakturering.lagKreditnota(for: f, context: db)
        #expect(k.sumEksMva == -5_000)

        Fakturering.ferdigstill(k, kunde: nil, mvaRegistrert: false, context: db)
        #expect(k.nummer == f.nummer + 1)
        #expect(k.status == .kreditert)
        #expect(f.status == .kreditert)
    }

    @Test func delvisKreditnotaGirLavereInntekt() throws {
        let db = try nyDatabase()
        let f = sendtFaktura(db, belop: 5_000)
        let k = Fakturering.lagKreditnota(for: f, context: db)
        k.sorterteLinjer.first?.enhetspris = 1_000
        Fakturering.ferdigstill(k, kunde: nil, mvaRegistrert: false, context: db)
        #expect(f.status == .sendt)
        #expect(Fakturering.gjenstaar(f, context: db) == 4_000)

        Fakturering.registrerBetalt(f, dato: .now, context: db)
        #expect(try db.fetch(FetchDescriptor<Inntekt>()).map(\.belop) == [4_000])
    }

    @Test func kreditnotaPaaBetaltFakturaTrekkesFraNaarDenBetalesTilbake() throws {
        let db = try nyDatabase()
        let f = sendtFaktura(db, belop: 3_000)
        Fakturering.registrerBetalt(f, dato: .now, context: db)
        let k = Fakturering.lagKreditnota(for: f, context: db)
        Fakturering.ferdigstill(k, kunde: nil, mvaRegistrert: false, context: db)
        #expect(k.status == .sendt)

        Fakturering.registrerBetalt(k, dato: .now, context: db)
        let sum = try db.fetch(FetchDescriptor<Inntekt>()).reduce(0) { $0 + $1.belop }
        #expect(sum == 0)
    }

    // MARK: Mva og skattemelding

    private func dag(_ aar: Int, _ maaned: Int, _ dag: Int) -> Date {
        Frister.kalender.date(from: DateComponents(year: aar, month: maaned, day: dag, hour: 12))!
    }

    @Test func mvaMeldingRegnerUtAaBetale() throws {
        let db = try nyDatabase()
        // Faktura i mars med 25 % mva: 10 000 + 2 500
        let f = sendtFaktura(db, belop: 10_000)
        f.mvaSats = 0.25
        f.fakturadato = dag(2026, 3, 10)
        // Mac kjøpt i Norge: 2 000 i mva, 100 % i foretaket
        let mac = Bilag(dato: dag(2026, 4, 2), tittel: "Mac", belop: 10_000, kategori: .driftsmiddel)
        mac.mva = 2_000
        db.insert(mac)
        // Claude fra utlandet: 200 kr, 50 % i foretaket
        let claude = Bilag(dato: dag(2026, 3, 5), tittel: "Claude", belop: 200, kategori: .programvare)
        claude.fraUtlandet = true
        claude.naeringsandel = 50
        db.insert(claude)
        // App Store i april, og noe utenfor perioden
        db.insert(Inntekt(dato: dag(2026, 4, 20), belop: 3_000, kilde: "App Store"))
        db.insert(Inntekt(dato: dag(2026, 5, 1), belop: 9_999, kilde: "App Store"))

        let m = MvaMelding(termin: Mva.Termin(aar: 2026, nr: 2), bilag: try db.fetch(FetchDescriptor<Bilag>()),
                           inntekter: try db.fetch(FetchDescriptor<Inntekt>()),
                           fakturaer: try db.fetch(FetchDescriptor<Faktura>()), mvaFra: nil)
        #expect(m.salgGrunnlag == 10_000)
        #expect(m.salgMva == 2_500)
        #expect(m.fritattUtland == 3_000)
        #expect(m.inngaendeMva == 2_000)
        #expect(m.utlandBeregnet == 50)
        #expect(m.utlandFradrag == 25)
        #expect(m.aaBetale == 2_500 + 50 - 2_000 - 25)
    }

    @Test func mvaMeldingTellerIkkeFoerRegistrering() throws {
        let db = try nyDatabase()
        let b = Bilag(dato: dag(2026, 3, 5), tittel: "Skjerm", belop: 2_500, kategori: .utstyr)
        b.mva = 500
        db.insert(b)
        let m = MvaMelding(termin: Mva.Termin(aar: 2026, nr: 2), bilag: [b], inntekter: [], fakturaer: [],
                           mvaFra: dag(2026, 4, 1))
        #expect(m.inngaendeMva == 0)
        #expect(b.fradrag(mvaRegistrert: true, mvaFra: dag(2026, 4, 1)) == 2_500)
        #expect(b.fradrag(mvaRegistrert: true, mvaFra: dag(2026, 3, 1)) == 2_000)
    }

    @Test func naeringsspesifikasjonenStemmerMedOverskuddet() throws {
        let db = try nyDatabase()
        let a = Bilag(dato: dag(2026, 2, 1), tittel: "GitHub", belop: 1_000, kategori: .programvare)
        let b = Bilag(dato: dag(2026, 6, 1), tittel: "Telefon", belop: 4_000, kategori: .telefonInternett)
        b.naeringsandel = 50
        db.insert(a)
        db.insert(b)
        db.insert(Inntekt(dato: dag(2026, 3, 1), belop: 20_000, kilde: "App Store"))
        db.insert(Inntekt(dato: dag(2026, 4, 1), belop: 8_000, kilde: "Faktura"))
        db.insert(Kjoretur(dato: dag(2026, 5, 1), fra: "Hjem", til: "Kunde", formal: "Møte", km: 100))
        let bilag = try db.fetch(FetchDescriptor<Bilag>())
        let inntekter = try db.fetch(FetchDescriptor<Inntekt>())
        let turer = try db.fetch(FetchDescriptor<Kjoretur>())

        let n = Naeringsspesifikasjon(aar: 2026, bilag: bilag, inntekter: inntekter, driftsmidler: [], turer: turer,
                                      mvaRegistrert: false, hjemmekontor: true, mvaFra: nil)
        let o = Aarsoversikt(aar: 2026, bilag: bilag, inntekter: inntekter, driftsmidler: [], turer: turer,
                             lonn: 0, mvaRegistrert: false, hjemmekontor: true)
        #expect(n.sumInntekter == 28_000)
        #expect(abs(n.resultat - o.overskudd) < 0.01)
        #expect(n.kostnader.contains { $0.konto == "6552" && $0.belop == 1_000 })
        #expect(n.kostnader.contains { $0.konto == "6900" && $0.belop == 2_000 })
    }

    // MARK: Takkebrev

    @Test func takkebrevetLaasesVedFerdigstilling() throws {
        let db = try nyDatabase()
        let f = Faktura()
        db.insert(f)
        f.medTakkebrev = true
        f.kundeNavn = "Trines Hundesalong"
        Fakturering.ferdigstill(f, kunde: nil, mvaRegistrert: false, context: db)
        #expect(!f.takketekst.isEmpty)
        #expect(f.harTakkebrev)

        f.takketekst = "Takk, {kunde}! Hilsen {firma}"
        f.selgerNavn = "Tillerflaten Digital"
        #expect(f.ferdigTakketekst == "Takk, Trines Hundesalong! Hilsen Tillerflaten Digital")
    }

    @Test func kreditnotaFaarIkkeTakkebrev() throws {
        let db = try nyDatabase()
        let f = sendtFaktura(db, belop: 1_000)
        f.medTakkebrev = true
        let k = Fakturering.lagKreditnota(for: f, context: db)
        k.medTakkebrev = true
        Fakturering.ferdigstill(k, kunde: nil, mvaRegistrert: false, context: db)
        #expect(!k.harTakkebrev)
        #expect(k.takketekst.isEmpty)
    }

    // MARK: Timebank

    private func prosjektMedTimer(_ db: ModelContext, timepris: Double, timer: [Double]) -> Prosjekt {
        let p = Prosjekt(navn: "Nettside")
        p.timepris = timepris
        db.insert(p)
        for (i, t) in timer.enumerated() {
            let f = Timeforing(dato: Date(timeIntervalSince1970: Double(i) * 86_400), timer: t, notat: i == 0 ? "Forside" : "")
            db.insert(f)
            f.prosjekt = p
        }
        try? db.save()
        return p
    }

    @Test func fakturaAvTimerFaarEnLinjePerDagOgMerkerTimene() throws {
        let db = try nyDatabase()
        let kunde = Kunde(navn: "Kafé Fjord")
        db.insert(kunde)
        let p = prosjektMedTimer(db, timepris: 750, timer: [2, 1.5])
        let f = Timebank.lagFaktura(for: p, foringer: p.foringer ?? [], kunde: kunde, context: db)

        #expect(f.kundeNavn == "Kafé Fjord")
        #expect(f.sorterteLinjer.map(\.antall) == [2, 1.5])
        #expect(f.sorterteLinjer.first?.beskrivelse.hasSuffix(": Forside") == true)
        #expect(f.sorterteLinjer.last?.beskrivelse.hasSuffix(": Nettside") == true)
        #expect(f.sumEksMva == 2_625)
        let ider = Set(try db.fetch(FetchDescriptor<Faktura>()).map(\.uuid))
        #expect(Timebank.ufakturerte(p.foringer ?? [], fakturaer: ider).isEmpty)
    }

    @Test func timeneBlirUfakturertNaarUtkastetSlettes() throws {
        let db = try nyDatabase()
        let p = prosjektMedTimer(db, timepris: 500, timer: [3])
        let f = Timebank.lagFaktura(for: p, foringer: p.foringer ?? [], kunde: nil, context: db)
        db.delete(f)
        try db.save()
        let ider = Set(try db.fetch(FetchDescriptor<Faktura>()).map(\.uuid))
        #expect(Timebank.sum(Timebank.ufakturerte(p.foringer ?? [], fakturaer: ider)) == 3)
    }

    @Test func effektivTimeprisPaaFastpris() {
        #expect(Timebank.effektivTimepris(pris: 7_500, timer: 50) == 150)
        #expect(Timebank.effektivTimepris(pris: 7_500, timer: 0) == nil)
    }

    @Test func prosjekterKommerMedISikkerhetskopien() throws {
        let gammel = try nyDatabase()
        let p = prosjektMedTimer(gammel, timepris: 600, timer: [1, 2])
        p.erFastpris = true
        p.fastpris = 9_000
        try gammel.save()

        let data = try Sikkerhetskopi.lag(fra: gammel).somData()
        let ny = try nyDatabase()
        _ = try Sikkerhetskopi.les(data).gjenopprett(til: ny)

        let hentet = try ny.fetch(FetchDescriptor<Prosjekt>())
        #expect(hentet.count == 1)
        #expect(hentet.first?.fastpris == 9_000)
        #expect(hentet.first?.sumTimer == 3)
    }

    @Test func sletteProsjektFjernerTimeneMenIkkeFakturaen() throws {
        let db = try nyDatabase()
        let p = prosjektMedTimer(db, timepris: 800, timer: [2, 3])
        let f = Timebank.lagFaktura(for: p, foringer: p.foringer ?? [], kunde: nil, context: db)
        db.delete(p)
        try db.save()
        #expect(try db.fetch(FetchDescriptor<Prosjekt>()).isEmpty)
        #expect(try db.fetch(FetchDescriptor<Timeforing>()).isEmpty)
        #expect(try db.fetch(FetchDescriptor<Faktura>()).first?.sumEksMva == 4_000)
        #expect(f.sorterteLinjer.count == 2)
    }

    // MARK: Avtaler

    private func dato(_ aar: Int, _ maaned: Int, _ dag: Int) -> Date {
        Frister.kalender.date(from: DateComponents(year: aar, month: maaned, day: dag))!
    }

    @Test func aarligLisensGirRiktigPeriodeOgFlyttesFram() throws {
        let db = try nyDatabase()
        let kunde = Kunde(navn: "TPTHK")
        db.insert(kunde)
        let a = Avtale(navn: "Lisens og support for medlemsside")
        a.belop = 6_000
        a.nestePeriodeFra = dato(2026, 11, 1)
        a.dagerFor = 14
        db.insert(a)

        #expect(a.nesteFakturadato == dato(2026, 10, 18))
        let f = Avtaler.lagFaktura(for: a, kunde: kunde, context: db)

        #expect(f.kundeNavn == "TPTHK")
        #expect(f.sorterteLinjer.first?.beskrivelse == "Lisens og support for medlemsside, 01.11.2026–31.10.2027")
        #expect(f.sumEksMva == 6_000)
        #expect(a.nestePeriodeFra == dato(2027, 11, 1))
    }

    @Test func maanedligPeriodeSlutterSisteDagIMaaneden() {
        #expect(Avtaler.periodeTil(fra: dato(2027, 2, 1), intervall: .maanedlig) == dato(2027, 2, 28))
        #expect(Avtaler.periodeTil(fra: dato(2026, 11, 1), intervall: .kvartalsvis) == dato(2027, 1, 31))
    }

    @Test func avtalerKommerMedISikkerhetskopien() throws {
        let gammel = try nyDatabase()
        let a = Avtale(navn: "Driftsavtale")
        a.belop = 390
        a.intervall = .maanedlig
        gammel.insert(a)
        try gammel.save()

        let data = try Sikkerhetskopi.lag(fra: gammel).somData()
        let ny = try nyDatabase()
        _ = try Sikkerhetskopi.les(data).gjenopprett(til: ny)

        let hentet = try ny.fetch(FetchDescriptor<Avtale>())
        #expect(hentet.first?.belop == 390)
        #expect(hentet.first?.intervall == .maanedlig)
    }

    // MARK: Dokumenter

    @Test func dokumenterPaaKunderOgAvtalerKommerMedISikkerhetskopien() throws {
        let gammel = try nyDatabase()
        let kunde = Kunde(navn: "TPTHK")
        gammel.insert(kunde)
        let tilbud = Dokument(navn: "Tilbud", filtype: "pdf", data: Data([1, 2, 3]))
        gammel.insert(tilbud)
        kunde.dokumenter = [tilbud]
        let avtale = Avtale(navn: "Lisens")
        gammel.insert(avtale)
        let kontrakt = Dokument(navn: "Signert avtale", filtype: "pdf", data: Data([4, 5]))
        gammel.insert(kontrakt)
        avtale.dokumenter = [kontrakt]
        try gammel.save()

        let data = try Sikkerhetskopi.lag(fra: gammel).somData()
        let ny = try nyDatabase()
        _ = try Sikkerhetskopi.les(data).gjenopprett(til: ny)

        #expect(try ny.fetch(FetchDescriptor<Kunde>()).first?.dokumenter?.first?.data == Data([1, 2, 3]))
        let hentet = try ny.fetch(FetchDescriptor<Avtale>()).first?.dokumenter?.first
        #expect(hentet?.navn == "Signert avtale")
        #expect(hentet?.data == Data([4, 5]))
    }

    @Test func dokumenteneSlettesMedAvtalen() throws {
        let db = try nyDatabase()
        let avtale = Avtale(navn: "Lisens")
        db.insert(avtale)
        let d = Dokument(navn: "Kontrakt", filtype: "pdf", data: Data([1]))
        db.insert(d)
        avtale.dokumenter = [d]
        try db.save()
        db.delete(avtale)
        try db.save()
        #expect(try db.fetch(FetchDescriptor<Dokument>()).isEmpty)
    }

    @Test func skannedeSiderBlirEnPdf() {
        let side = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 140)).image { _ in }
        let pdf = Dokumenter.pdf(av: [side, side])
        #expect(pdf.starts(with: Data("%PDF".utf8)))
    }
}
