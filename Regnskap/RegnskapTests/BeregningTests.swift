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
