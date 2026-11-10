import SwiftUI

// MARK: Regnestykket

/// Logikken bak kalkulatoren: tar imot tastetrykk og regner ut svaret.
/// Ganging og deling regnes før pluss og minus, som på en vanlig kalkulator.
/// Regner med `Decimal`, så 0,1 + 0,2 blir 0,3 og ikke 0,30000000000000004.
struct Regnestykke: Equatable {
    enum Regneart: String, CaseIterable {
        case pluss = "+", minus = "−", gange = "×", dele = "÷"
    }

    enum Ledd: Equatable {
        case tall(String)        // Slik det er skrevet, med komma: «1234,5»
        case regneart(Regneart)
    }

    private(set) var ledd: [Ledd] = []
    /// Sant når tallet som står der er et svar eller det gamle beløpet.
    /// Neste siffer begynner da på et nytt tall i stedet for å skrive videre.
    private var ferskt = false

    static let maksSiffer = 12
    static let maksDesimaler = 2

    init() {}

    /// Starter med beløpet som allerede står i feltet.
    init(belop: Double) {
        if belop != 0 {
            ledd = [.tall(Self.tekst(Decimal(belop)))]
            ferskt = true
        }
    }

    var erTomt: Bool { ledd.isEmpty }

    /// Sant når det står mer enn ett tall, altså et regnestykke og ikke bare et beløp.
    var harRegning: Bool { ledd.contains { if case .regneart = $0 { true } else { false } } }

    // MARK: Taster

    mutating func siffer(_ s: Character) {
        guard s.isNumber else { return }
        if ferskt { ledd.removeAll(); ferskt = false }
        guard case .tall(var tall) = ledd.last else {
            ledd.append(.tall(String(s)))
            return
        }
        if let komma = tall.firstIndex(of: ",") {
            guard tall[tall.index(after: komma)...].count < Self.maksDesimaler else { return }
        } else {
            guard tall.filter(\.isNumber).count < Self.maksSiffer else { return }
        }
        if tall == "0" { tall = "" }
        if tall == "-0" { tall = "-" }
        tall.append(s)
        ledd[ledd.count - 1] = .tall(tall)
    }

    mutating func komma() {
        if ferskt { ledd.removeAll(); ferskt = false }
        guard case .tall(var tall) = ledd.last else {
            ledd.append(.tall("0,"))
            return
        }
        guard !tall.contains(",") else { return }
        if tall.isEmpty || tall == "-" { tall.append("0") }
        tall.append(",")
        ledd[ledd.count - 1] = .tall(tall)
    }

    mutating func regneart(_ r: Regneart) {
        ferskt = false
        switch ledd.last {
        case nil:
            // Uten tall først regner vi fra 0, så «− 50» blir minus 50.
            ledd = [.tall("0"), .regneart(r)]
        case .regneart:
            // Trykket feil regneart: bytt den ut.
            ledd[ledd.count - 1] = .regneart(r)
        case .tall:
            ledd.append(.regneart(r))
        }
    }

    mutating func slett() {
        ferskt = false
        guard let siste = ledd.last else { return }
        switch siste {
        case .regneart:
            ledd.removeLast()
        case .tall(var tall):
            tall.removeLast()
            if tall.isEmpty || tall == "-" { ledd.removeLast() } else { ledd[ledd.count - 1] = .tall(tall) }
        }
    }

    mutating func nullstill() {
        ledd.removeAll()
        ferskt = false
    }

    /// Regner ut og setter svaret inn som nytt utgangspunkt.
    mutating func erLik() {
        guard harRegning, let svar else { return }
        ledd = svar == 0 ? [] : [.tall(Self.tekst(svar))]
        ferskt = true
    }

    // MARK: Utregning

    /// Svaret, avrundet til to desimaler. `nil` hvis det deles på null.
    /// En regneart til slutt («100 +») hoppes over.
    var svar: Decimal? {
        var deler = ledd
        if case .regneart = deler.last { deler.removeLast() }
        guard !deler.isEmpty else { return 0 }

        // Først ganging og deling, så pluss og minus.
        var summer: [(Regneart, Decimal)] = []
        var gjeldende: Decimal = 0
        var fortegn = Regneart.pluss
        var venter: Regneart?

        for del in deler {
            switch del {
            case .tall(let tekst):
                let verdi = Self.tall(tekst)
                switch venter {
                case .gange: gjeldende *= verdi
                case .dele:
                    guard verdi != 0 else { return nil }
                    gjeldende /= verdi
                default: gjeldende = verdi
                }
                venter = nil
            case .regneart(let r):
                if r == .gange || r == .dele {
                    venter = r
                } else {
                    summer.append((fortegn, gjeldende))
                    fortegn = r
                    gjeldende = 0
                }
            }
        }
        summer.append((fortegn, gjeldende))

        let sum = summer.reduce(Decimal(0)) { $1.0 == .minus ? $0 - $1.1 : $0 + $1.1 }
        return Self.avrund(sum)
    }

    /// Regnestykket slik det vises, med mellomrom som tusenskille: «1 234,5 + 300».
    var visning: String {
        ledd.map { del in
            switch del {
            case .tall(let tekst): Self.medTusenskille(tekst)
            case .regneart(let r): r.rawValue
            }
        }
        .joined(separator: " ")
    }

    // MARK: Hjelpere

    private static func tall(_ tekst: String) -> Decimal {
        var renset = tekst.replacingOccurrences(of: ",", with: ".")
        if renset.hasSuffix(".") { renset.removeLast() }
        return Decimal(string: renset, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    static func avrund(_ verdi: Decimal) -> Decimal {
        var inn = verdi
        var ut = Decimal()
        NSDecimalRound(&ut, &inn, maksDesimaler, .plain)
        return ut
    }

    /// 1234.5 → «1234,5» (uten tusenskille, slik man skriver det).
    static func tekst(_ verdi: Decimal) -> String {
        let avrundet = avrund(verdi)
        return NSDecimalNumber(decimal: avrundet).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    /// «1234567,5» → «1 234 567,5»
    static func medTusenskille(_ tekst: String) -> String {
        let minus = tekst.hasPrefix("-")
        let utenMinus = minus ? String(tekst.dropFirst()) : tekst
        let deler = utenMinus.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let heltall = String(deler.first ?? "")
        var gruppert = ""
        for (i, tegn) in heltall.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { gruppert.append("\u{202F}") }
            gruppert.append(tegn)
        }
        var resultat = (minus ? "−" : "") + String(gruppert.reversed())
        if deler.count > 1 { resultat += "," + deler[1] }
        return resultat
    }

    static func vis(_ verdi: Decimal) -> String {
        medTusenskille(tekst(verdi))
    }
}

// MARK: Feltet

/// Rad for beløp. Trykk på raden, så åpnes en kalkulator med store taster.
/// Du kan skrive et beløp rett inn, eller regne det ut («1 200 × 3», «2 450 − 300»).
/// Feltet viser ingenting når beløpet er 0.
struct BelopFelt: View {
    let tittel: String
    @Binding var belop: Double
    let enhet: String
    /// Valgfri ekstralinje i kalkulatoren som følger med mens du skriver,
    /// f.eks. hva beløpet blir i kroner i valutakalkulatoren.
    let forhandsvisning: ((Double) -> String?)?

    @State private var visKalkulator = false

    init(_ tittel: String, belop: Binding<Double>, enhet: String = "kr",
         forhandsvisning: ((Double) -> String?)? = nil) {
        self.tittel = tittel
        self._belop = belop
        self.enhet = enhet
        self.forhandsvisning = forhandsvisning
    }

    var body: some View {
        Button {
            visKalkulator = true
        } label: {
            HStack {
                Text(tittel)
                    .foregroundStyle(.primary)
                Spacer()
                Text(belop == 0 ? "0" : Self.vis(belop))
                    .monospacedDigit()
                    .foregroundStyle(belop == 0 ? .tertiary : .primary)
                if !enhet.isEmpty {
                    Text(enhet)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "plus.forwardslash.minus")
                    .font(.footnote)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tittel)
        .accessibilityValue(belop == 0 ? "Tomt" : "\(Self.vis(belop)) \(enhet)")
        .accessibilityHint("Åpner kalkulatoren")
        .sheet(isPresented: $visKalkulator) {
            KalkulatorView(tittel: tittel, belop: $belop, enhet: enhet, forhandsvisning: forhandsvisning)
        }
    }

    private static func vis(_ verdi: Double) -> String {
        verdi.formatted(.number.precision(.fractionLength(0...2)))
    }
}

// MARK: Kalkulatoren

struct KalkulatorView: View {
    let tittel: String
    @Binding var belop: Double
    let enhet: String
    let forhandsvisning: ((Double) -> String?)?

    @Environment(\.dismiss) private var dismiss
    @State private var stykke: Regnestykke

    init(tittel: String, belop: Binding<Double>, enhet: String,
         forhandsvisning: ((Double) -> String?)? = nil) {
        self.tittel = tittel
        self._belop = belop
        self.enhet = enhet
        self.forhandsvisning = forhandsvisning
        self._stykke = State(initialValue: Regnestykke(belop: belop.wrappedValue))
    }

    private var svar: Decimal? { stykke.svar }
    private var svarSomTall: Double? { svar.map { NSDecimalNumber(decimal: $0).doubleValue } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                skjerm
                tastatur
                Button {
                    bruk()
                } label: {
                    Text("Bruk beløpet")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(svar == nil)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color.temaBakgrunn.ignoresSafeArea())
            .navigationTitle(tittel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: stykke)
    }

    // MARK: Skjermen øverst

    private var skjerm: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Regnestykket på en linje, svaret stort under.
            Text(stykke.harRegning ? stykke.visning : " ")
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Spacer(minLength: 0)
                Text(hovedtekst)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(svar == nil ? Color.red : (stykke.erTomt ? Color.secondary : Color.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                if !enhet.isEmpty {
                    Text(enhet)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            if let svarSomTall, let ekstra = forhandsvisning?(svarSomTall) {
                Text(ekstra)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding()
        .background(Color.temaFlate, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .animation(.snappy(duration: 0.15), value: stykke)
    }

    private var hovedtekst: String {
        guard let svar else { return "Kan ikke dele på 0" }
        if stykke.erTomt { return "0" }
        if stykke.harRegning { return Regnestykke.vis(svar) }
        // Bare ett tall: vis det nøyaktig slik det er skrevet, også «12,» underveis.
        return stykke.visning
    }

    // MARK: Tastene

    private enum Tast: Hashable {
        case siffer(Character), komma, regneart(Regnestykke.Regneart), slett, nullstill, erLik
    }

    private let rader: [[Tast]] = [
        [.nullstill, .slett, .regneart(.dele), .regneart(.gange)],
        [.siffer("7"), .siffer("8"), .siffer("9"), .regneart(.minus)],
        [.siffer("4"), .siffer("5"), .siffer("6"), .regneart(.pluss)],
        [.siffer("1"), .siffer("2"), .siffer("3"), .erLik],
    ]

    private var tastatur: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rader, id: \.self) { rad in
                GridRow {
                    ForEach(rad, id: \.self) { tast in
                        tastKnapp(tast)
                    }
                }
            }
            GridRow {
                tastKnapp(.siffer("0"))
                    .gridCellColumns(2)
                tastKnapp(.komma)
                // Tom plass under = så 0 og komma står der man venter dem.
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .frame(maxHeight: 440)
    }

    private func tastKnapp(_ tast: Tast) -> some View {
        Button {
            trykk(tast)
        } label: {
            etikett(tast)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 54)
                .background(farge(tast), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(tekstfarge(tast))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(Trykkeffekt())
        .accessibilityLabel(navn(tast))
    }

    @ViewBuilder
    private func etikett(_ tast: Tast) -> some View {
        switch tast {
        case .siffer(let s): Text(String(s))
        case .komma: Text(",")
        case .regneart(let r): Text(r.rawValue)
        case .slett: Image(systemName: "delete.left")
        case .nullstill: Text("C")
        case .erLik: Text("=")
        }
    }

    private func farge(_ tast: Tast) -> Color {
        switch tast {
        case .siffer, .komma: Color.temaFlate
        case .regneart, .erLik: Color.temaAksentMyk
        case .slett, .nullstill: Color.secondary.opacity(0.15)
        }
    }

    private func tekstfarge(_ tast: Tast) -> Color {
        switch tast {
        case .regneart, .erLik: Color.accentColor
        default: Color.primary
        }
    }

    private func navn(_ tast: Tast) -> String {
        switch tast {
        case .siffer(let s): String(s)
        case .komma: "Komma"
        case .regneart(.pluss): "Pluss"
        case .regneart(.minus): "Minus"
        case .regneart(.gange): "Gange"
        case .regneart(.dele): "Dele"
        case .slett: "Slett"
        case .nullstill: "Nullstill"
        case .erLik: "Er lik"
        }
    }

    private func trykk(_ tast: Tast) {
        switch tast {
        case .siffer(let s): stykke.siffer(s)
        case .komma: stykke.komma()
        case .regneart(let r): stykke.regneart(r)
        case .slett: stykke.slett()
        case .nullstill: stykke.nullstill()
        case .erLik: stykke.erLik()
        }
    }

    private func bruk() {
        guard let svarSomTall else { return }
        belop = svarSomTall
        dismiss()
    }
}

/// Tasten krymper litt når du trykker, så du kjenner at den tok imot.
private struct Trykkeffekt: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
