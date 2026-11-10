import Foundation
import Testing
@testable import Regnskap

struct KalkulatorTests {
    private func trykk(_ taster: String, start: Double = 0) -> Regnestykke {
        var r = Regnestykke(belop: start)
        for t in taster {
            switch t {
            case ",": r.komma()
            case "+": r.regneart(.pluss)
            case "-": r.regneart(.minus)
            case "*": r.regneart(.gange)
            case "/": r.regneart(.dele)
            case "<": r.slett()
            case "C": r.nullstill()
            case "=": r.erLik()
            default: r.siffer(t)
            }
        }
        return r
    }

    @Test func vanligBelop() {
        #expect(trykk("1234,5").svar == Decimal(string: "1234.5"))
    }

    @Test func gangingForPluss() {
        #expect(trykk("2+3*4").svar == 14)
        #expect(trykk("100-20/4").svar == 95)
    }

    @Test func desimalerUtenAvrundingsfeil() {
        #expect(trykk("0,1+0,2").svar == Decimal(string: "0.3"))
    }

    @Test func svaretAvrundesTilToDesimaler() {
        #expect(trykk("10/3").svar == Decimal(string: "3.33"))
        #expect(trykk("10/3*3").svar == 10)
    }

    @Test func deleMedNullGirIngenSvar() {
        #expect(trykk("5/0").svar == nil)
    }

    @Test func regneartTilSlutHoppesOver() {
        #expect(trykk("100+").svar == 100)
    }

    @Test func nyRegneartBytterUtDenForrige() {
        #expect(trykk("100+-20").svar == 80)
    }

    @Test func maksToDesimaler() {
        #expect(trykk("1,239").svar == Decimal(string: "1.23"))
    }

    @Test func slettFjernerSisteTegn() {
        #expect(trykk("123<").svar == 12)
        #expect(trykk("12+<5").svar == 125)
    }

    @Test func gammeltBelopErstattesAvNyttTall() {
        #expect(trykk("50", start: 1200).svar == 50)
    }

    @Test func gammeltBelopKanRegnesVidereMed() {
        #expect(trykk("*3", start: 1200).svar == 3600)
    }

    @Test func erLikGirNyttUtgangspunkt() {
        let r = trykk("1200*3=")
        #expect(r.svar == 3600)
        #expect(!r.harRegning)
        #expect(trykk("1200*3=-600").svar == 3000)
    }

    @Test func kommaForstGirNullKomma() {
        #expect(trykk(",5").visning == "0,5")
    }

    @Test func visningMedTusenskille() {
        #expect(Regnestykke.medTusenskille("1234567,5") == "1\u{202F}234\u{202F}567,5")
    }
}
