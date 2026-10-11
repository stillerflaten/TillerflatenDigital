import Foundation
import Testing
@testable import Regnskap

// Fasit er regnet ut for hånd med 2026-satsene.
struct SkattTests {
    let satser = Skattesatser.aar2026

    @Test func overskuddOppaaPolitilonnSkattesMed36_8Prosent() {
        // 650 000 i lønn ligger i trinn 2 (4 %). Neste krone: 22 % + 10,8 % + 4 % = 36,8 %.
        let s = EnkSkatt(lonn: 650_000, overskudd: 60_000, satser: satser)
        #expect(abs(s.ekstraSkatt - 22_080) < 1)
        #expect(abs(s.marginalsats - 0.368) < 0.0001)
        #expect(abs(s.ekstraTrygdeavgift - 6_480) < 1)
        #expect(abs(s.ekstraInntektsskatt - 13_200) < 1)
        #expect(abs(s.ekstraTrinnskatt - 2_400) < 1)
    }

    @Test func storreOverskuddKryssesTrinn3() {
        // 650 000 + 200 000 = 850 000 passerer trinn 3 (725 050).
        let s = EnkSkatt(lonn: 650_000, overskudd: 200_000, satser: satser)
        #expect(abs(s.ekstraSkatt - 85_720) < 1)
        #expect(abs(s.marginalsats - 0.465) < 0.0001)
    }

    @Test func underskuddGirLavereSkatt() {
        let s = EnkSkatt(lonn: 650_000, overskudd: -20_000, satser: satser)
        // Underskuddet trekkes bare fra i alminnelig inntekt (22 %).
        #expect(abs(s.ekstraSkatt - -4_400) < 1)
    }

    @Test func ingenSkattUnderGrensene() {
        let s = Skatteberegning(lonn: 0, naeringsoverskudd: 60_000, satser: satser)
        #expect(s.sum == 0)
    }
}

struct AvskrivningTests {
    let satser = Skattesatser.aar2026

    @Test func billigUtstyrTrekkesFraDirekte() {
        #expect(Avskrivning.metode(kostpris: 29_990, gruppe: .a, satser: satser) == .direkteFradrag(belop: 29_990))
        #expect(Avskrivning.metode(kostpris: 40_000, naeringsandel: 0.5, gruppe: .a, satser: satser)
                == .saldo(gruppe: .a, grunnlag: 20_000))
        #expect(Avskrivning.metode(kostpris: 40_000, levetidMinst3Aar: false, gruppe: .a, satser: satser)
                == .direkteFradrag(belop: 40_000))
    }

    @Test func macTil45000AvskrivesIGruppeA() {
        let plan = Avskrivning.plan(forEttKjop: 45_000, aar: 2026, gruppe: .a, satser: satser)
        // 2026: 30 % av 45 000 = 13 500, rest 31 500
        // 2027: 30 % av 31 500 = 9 450, rest 22 050
        // 2028: under 30 000, hele resten trekkes fra
        #expect(plan.map(\.avskrivning) == [13_500, 9_450, 22_050])
        #expect(plan.last?.lavSaldoFradrag == true)
        #expect(plan.last?.utgaende == 0)
    }

    @Test func flereKjopISammeGruppeSlaasSammen() {
        let plan = Avskrivning.saldoplan(anskaffelser: [(2026, 40_000), (2027, 35_000)], gruppe: .a,
                                         tilOgMed: 2027, satser: satser)
        #expect(plan.count == 2)
        #expect(plan[0].avskrivning == 12_000)       // 30 % av 40 000
        #expect(plan[1].grunnlag == 28_000 + 35_000)  // rest + nytt kjøp
        #expect(plan[1].avskrivning == 18_900)        // 30 % av 63 000
    }
}

struct FristTests {
    @Test func forskuddsskattFireGangerIAaret() {
        let frister = Frister.liste(for: 2026, forskuddsskatt: true, mvaRegistrert: false, mvaAarstermin: false)
        let forskudd = frister.filter { $0.slag == .forskuddsskatt }
        #expect(forskudd.count == 4)
        let cal = Frister.kalender
        // 15. mars 2026 er en søndag, så fristen flyttes til mandag 16. mars.
        #expect(cal.component(.day, from: forskudd[0].dato) == 16)
        #expect(forskudd.map { cal.component(.month, from: $0.dato) } == [3, 6, 9, 12])
    }

    @Test func mvaTerminerBareNaarRegistrert() {
        let uten = Frister.liste(for: 2026, forskuddsskatt: false, mvaRegistrert: false, mvaAarstermin: false)
        #expect(uten.allSatisfy { $0.slag != .mva })
        let med = Frister.liste(for: 2026, forskuddsskatt: false, mvaRegistrert: true, mvaAarstermin: false)
        #expect(med.filter { $0.slag == .mva }.count == 6)
        let aarstermin = Frister.liste(for: 2026, forskuddsskatt: false, mvaRegistrert: true, mvaAarstermin: true)
        #expect(aarstermin.filter { $0.slag == .mva }.count == 1)
    }
}

struct ArkivTests {
    private func dato(_ aar: Int, _ maaned: Int, _ dag: Int) -> Date {
        Frister.kalender.date(from: DateComponents(year: aar, month: maaned, day: dag))!
    }

    @Test func ifjorErIBrukFremTilSkattemeldingen() {
        #expect(Arkiv.erAktivt(2026, naa: dato(2026, 3, 1)))
        #expect(Arkiv.erAktivt(2025, naa: dato(2026, 5, 31)))
        #expect(!Arkiv.erAktivt(2025, naa: dato(2026, 6, 1)))
        #expect(!Arkiv.erAktivt(2024, naa: dato(2026, 1, 10)))
    }

    @Test func filnavnHarDatoOgIngenUlovligeTegn() {
        #expect(Arkiv.filnavn(dato: dato(2025, 3, 14), tittel: "Kabel 1/2") == "2025-03-14 Kabel 1-2")
        #expect(Arkiv.filnavn(dato: dato(2025, 3, 14), tittel: " ") == "2025-03-14")
    }
}

struct FakturaTests {
    @Test func nummerFortsetterUtenHull() {
        #expect(Fakturering.nesteNummer(brukte: [], startnummer: 1) == 1)
        #expect(Fakturering.nesteNummer(brukte: [1, 2, 3], startnummer: 1) == 4)
        // Har du brukt et annet program før, starter appen der du slapp.
        #expect(Fakturering.nesteNummer(brukte: [], startnummer: 15) == 15)
        #expect(Fakturering.nesteNummer(brukte: [15, 16], startnummer: 15) == 17)
    }

    @Test func kontonrOgOrgnrFormateres() {
        #expect(Fakturering.kontonr("12345678901") == "1234 56 78901")
        #expect(Fakturering.kontonr("1234.56.78901") == "1234 56 78901")
        #expect(Fakturering.orgnr("123456789") == "123 456 789")
        #expect(Fakturering.orgnr("12345") == "12345")
    }

    @Test func linjebelopRundesTilOre() {
        #expect(Fakturering.rund(2.5 * 333.333) == 833.33)
    }
}

struct FasteUtgifterTests {
    @Test func nesteTrekkFlyttesEttIntervallFram() {
        let cal = Frister.kalender
        let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let neste = FasteUtgifter.neste(etter: start, intervall: .maanedlig)
        #expect(cal.dateComponents([.month, .day], from: neste) == DateComponents(month: 2, day: 28))
        let aar = FasteUtgifter.neste(etter: start, intervall: .aarlig)
        #expect(cal.component(.year, from: aar) == 2027)
    }
}

struct AutoKopiTests {
    @Test func filnavnHarDato() {
        let d = Frister.kalender.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
        #expect(AutoKopi.filnavn(for: d) == "Regnskap 2026-03-07.json")
    }

    @Test func beholderDeNyesteOgEnPerMaaned() {
        // Daglige kopier fra 1. januar til 30. september.
        var filer: [String] = []
        for m in 1...9 {
            for dag in 1...28 {
                filer.append(String(format: "Regnskap 2026-%02d-%02d.json", m, dag))
            }
        }
        filer.append("Notater.txt")
        filer.append("Regnskap sikkerhetskopi 2026-01-01.json")

        let slett = Set(AutoKopi.filerSomSkalSlettes(filer))
        let behold = Set(filer).subtracting(slett)

        #expect(!slett.contains("Notater.txt"))
        #expect(!slett.contains("Regnskap sikkerhetskopi 2026-01-01.json"))
        // De fem nyeste, pluss den nyeste fra april–august (september er dekket av de fem).
        for dag in 24...28 { #expect(behold.contains(String(format: "Regnskap 2026-09-%02d.json", dag))) }
        for m in 4...8 { #expect(behold.contains(String(format: "Regnskap 2026-%02d-28.json", m))) }
        #expect(behold.count == 5 + 5 + 2)
        #expect(slett.contains("Regnskap 2026-03-28.json"))
    }

    @Test func faaFilerSlettesIkke() {
        let filer = ["Regnskap 2026-10-01.json", "Regnskap 2026-10-02.json"]
        #expect(AutoKopi.filerSomSkalSlettes(filer).isEmpty)
    }
}

struct MvaTerminTests {
    @Test func terminerDekkerToMaaneder() {
        let t = Mva.Termin(aar: 2026, nr: 3)
        let mai = Frister.kalender.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let juli = Frister.kalender.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        #expect(t.fra == mai)
        #expect(t.til == juli)
        #expect(Mva.Termin.gjeldende(Frister.kalender.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12))!, aarstermin: false).nr == 6)
        #expect(Mva.Termin.gjeldende(mai, aarstermin: true).nr == 0)
    }

    @Test func synkSammenlignerVerdier() {
        #expect(InnstillingSynk.erLike(nil, nil))
        #expect(InnstillingSynk.erLike(500_000.0, 500_000.0))
        #expect(!InnstillingSynk.erLike("a", "b"))
        #expect(!InnstillingSynk.erLike(true, nil))
    }
}
