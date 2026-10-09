import Foundation

/// Skatten for én person med lønn + overskudd fra enkeltpersonforetak.
/// Forenklet: tar ikke med renter, formue, fagforeningskontingent osv.
/// Bruk «andre fradrag» til å legge inn slikt grovt hvis du vil.
struct Skatteberegning {
    let alminneligInntektsskatt: Double
    let trinnskatt: Double
    let trygdeavgift: Double

    var sum: Double { alminneligInntektsskatt + trinnskatt + trygdeavgift }

    init(lonn: Double, naeringsoverskudd: Double, andreFradrag: Double = 0, satser s: Skattesatser) {
        let lonn = max(0, lonn)
        let minstefradrag = min(lonn * s.minstefradragSats, s.minstefradragMaks)

        // Underskudd i foretaket kan trekkes fra i alminnelig inntekt,
        // men gir ikke negativ personinntekt (det fremføres i stedet).
        let alminnelig = max(0, lonn - minstefradrag + naeringsoverskudd - andreFradrag - s.personfradrag)
        alminneligInntektsskatt = alminnelig * s.alminneligSats

        let naeringPersoninntekt = max(0, naeringsoverskudd)
        let personinntekt = lonn + naeringPersoninntekt

        var trinn = 0.0
        for (i, steg) in s.trinnskatt.enumerated() {
            guard personinntekt > steg.grense else { break }
            let tak = i + 1 < s.trinnskatt.count ? s.trinnskatt[i + 1].grense : .infinity
            trinn += (min(personinntekt, tak) - steg.grense) * steg.sats
        }
        trinnskatt = trinn

        if personinntekt <= s.trygdeavgiftNedreGrense {
            trygdeavgift = 0
        } else {
            let ordinaer = lonn * s.trygdeavgiftLonn + naeringPersoninntekt * s.trygdeavgiftNaering
            let tak = (personinntekt - s.trygdeavgiftNedreGrense) * s.trygdeavgiftOpptrapping
            trygdeavgift = min(ordinaer, tak)
        }
    }
}

/// Hvor mye ekstra skatt foretaket gir, sammenlignet med bare lønn.
struct EnkSkatt {
    let utenForetak: Skatteberegning
    let medForetak: Skatteberegning
    /// Skatt på neste krone overskudd (marginalskatt), 0–1
    let marginalsats: Double

    var ekstraSkatt: Double { medForetak.sum - utenForetak.sum }
    var ekstraInntektsskatt: Double { medForetak.alminneligInntektsskatt - utenForetak.alminneligInntektsskatt }
    var ekstraTrinnskatt: Double { medForetak.trinnskatt - utenForetak.trinnskatt }
    var ekstraTrygdeavgift: Double { medForetak.trygdeavgift - utenForetak.trygdeavgift }

    /// Andel av overskuddet som går til skatt, 0–1
    func andel(av overskudd: Double) -> Double {
        overskudd > 0 ? ekstraSkatt / overskudd : 0
    }

    init(lonn: Double, overskudd: Double, andreFradrag: Double = 0, satser: Skattesatser) {
        utenForetak = Skatteberegning(lonn: lonn, naeringsoverskudd: 0, andreFradrag: andreFradrag, satser: satser)
        medForetak = Skatteberegning(lonn: lonn, naeringsoverskudd: overskudd, andreFradrag: andreFradrag, satser: satser)
        let steg = 1_000.0
        let neste = Skatteberegning(lonn: lonn, naeringsoverskudd: max(0, overskudd) + steg, andreFradrag: andreFradrag, satser: satser)
        let her = Skatteberegning(lonn: lonn, naeringsoverskudd: max(0, overskudd), andreFradrag: andreFradrag, satser: satser)
        marginalsats = (neste.sum - her.sum) / steg
    }
}
