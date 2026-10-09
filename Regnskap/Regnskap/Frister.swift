import Foundation

struct Frist: Identifiable, Hashable {
    enum Slag: String {
        case forskuddsskatt, skattemelding, mva
    }

    let id: String
    let dato: Date
    let tittel: String
    let forklaring: String
    let slag: Slag

    var ikon: String {
        switch slag {
        case .forskuddsskatt: "banknote"
        case .skattemelding: "doc.text"
        case .mva: "percent"
        }
    }
}

enum Frister {
    static var kalender: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return cal
    }

    /// Lager en dato. Faller den på lørdag eller søndag, flyttes den til mandag.
    /// (Helligdager er ikke med; sjekk Skatteetaten rundt påske og jul.)
    static func dato(_ aar: Int, _ maaned: Int, _ dag: Int) -> Date {
        let cal = kalender
        var d = cal.date(from: DateComponents(year: aar, month: maaned, day: dag, hour: 12))!
        while cal.isDateInWeekend(d) {
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return d
    }

    /// Alle frister som har forfall i kalenderåret `aar`.
    static func liste(for aar: Int, forskuddsskatt: Bool, mvaRegistrert: Bool, mvaAarstermin: Bool) -> [Frist] {
        var frister: [Frist] = []

        frister.append(Frist(
            id: "skattemelding-\(aar)",
            dato: dato(aar, 5, 31),
            tittel: "Skattemelding for \(aar - 1)",
            forklaring: "Skattemeldingen for næringsdrivende med næringsspesifikasjon for \(aar - 1) skal leveres. Du kan søke om utsettelse i Altinn.",
            slag: .skattemelding))

        if forskuddsskatt {
            for (nr, maaned) in [3, 6, 9, 12].enumerated() {
                frister.append(Frist(
                    id: "forskudd-\(aar)-\(nr + 1)",
                    dato: dato(aar, maaned, 15),
                    tittel: "Forskuddsskatt, termin \(nr + 1) av 4",
                    forklaring: "Betal forskuddsskatt for \(aar). Beløpet og KID står i Skatteetatens betalingsoversikt.",
                    slag: .forskuddsskatt))
            }
        }

        if mvaRegistrert {
            if mvaAarstermin {
                frister.append(Frist(
                    id: "mva-aar-\(aar)",
                    dato: dato(aar, 3, 10),
                    tittel: "Mva-melding for \(aar - 1) (årstermin)",
                    forklaring: "Lever mva-meldingen for hele \(aar - 1) og betal eventuell mva.",
                    slag: .mva))
            } else {
                // (termin, forfallsmåned, dag, år terminen gjelder)
                let terminer: [(Int, Int, Int, Int)] = [
                    (6, 2, 10, aar - 1), (1, 4, 10, aar), (2, 6, 10, aar),
                    (3, 8, 31, aar), (4, 10, 10, aar), (5, 12, 10, aar),
                ]
                let perioder = ["", "jan–feb", "mar–apr", "mai–jun", "jul–aug", "sep–okt", "nov–des"]
                for (termin, maaned, dag, gjelder) in terminer {
                    frister.append(Frist(
                        id: "mva-\(aar)-\(maaned)",
                        dato: dato(aar, maaned, dag),
                        tittel: "Mva-melding, termin \(termin) \(gjelder)",
                        forklaring: "Lever mva-meldingen for \(perioder[termin]) \(gjelder) og betal eventuell mva.",
                        slag: .mva))
                }
            }
        }

        return frister.sorted { $0.dato < $1.dato }
    }

    /// Frister fra og med i dag, for i år og neste år.
    static func kommende(fra idag: Date = .now, forskuddsskatt: Bool, mvaRegistrert: Bool, mvaAarstermin: Bool) -> [Frist] {
        let aar = kalender.component(.year, from: idag)
        let start = kalender.startOfDay(for: idag)
        return (liste(for: aar, forskuddsskatt: forskuddsskatt, mvaRegistrert: mvaRegistrert, mvaAarstermin: mvaAarstermin)
                + liste(for: aar + 1, forskuddsskatt: forskuddsskatt, mvaRegistrert: mvaRegistrert, mvaAarstermin: mvaAarstermin))
            .filter { $0.dato >= start }
    }

    /// Hvor mange forskuddsskatt-terminer som gjenstår i år (brukes til å fordele skatten).
    static func gjenstaendeForskuddsterminer(fra idag: Date = .now) -> Int {
        let aar = kalender.component(.year, from: idag)
        let start = kalender.startOfDay(for: idag)
        return liste(for: aar, forskuddsskatt: true, mvaRegistrert: false, mvaAarstermin: false)
            .filter { $0.slag == .forskuddsskatt && $0.dato >= start }
            .count
    }
}
