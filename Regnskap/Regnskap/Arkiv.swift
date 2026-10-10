import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Hvilke år som er «i bruk» og hvilke som ligger i arkivet.
/// Ingenting slettes: arkiverte år vises bare et annet sted.
enum Arkiv {
    /// I år, og i fjor helt til skattemeldingen er levert (31. mai).
    static func erAktivt(_ aar: Int, naa: Date = .now) -> Bool {
        let iAar = naa.aar
        if aar >= iAar { return true }
        if aar == iAar - 1 {
            let maaned = Frister.kalender.component(.month, from: naa)
            return maaned <= 5
        }
        return false
    }

    /// Bilag skal oppbevares i fem år etter utgangen av regnskapsåret (bokføringsloven § 13).
    static func oppbevaresTil(_ aar: Int) -> Int { aar + 5 }

    /// Lager et trygt filnavn: «2025-03-14 Apple Developer Program».
    static func filnavn(dato: Date, tittel: String) -> String {
        let d = Frister.kalender.dateComponents([.year, .month, .day], from: dato)
        let dag = String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
        let ulovlige = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let renset = tittel.components(separatedBy: ulovlige).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return renset.isEmpty ? dag : "\(dag) \(renset.prefix(60))"
    }
}

/// Liste med alle år som har noe registrert, nyeste først.
struct ArkivView: View {
    @Query(sort: \Bilag.dato, order: .reverse) private var bilag: [Bilag]
    @Query(sort: \Inntekt.dato, order: .reverse) private var inntekter: [Inntekt]
    @Query private var turer: [Kjoretur]

    private var aarene: [Int] {
        Set(bilag.map(\.dato.aar) + inntekter.map(\.dato.aar) + turer.map(\.dato.aar))
            .sorted(by: >)
    }

    var body: some View {
        List {
            if aarene.isEmpty {
                ContentUnavailableView("Arkivet er tomt", systemImage: "archivebox",
                                       description: Text("Når du har registrert bilag eller inntekter, finner du hvert år her."))
            }
            Section {
                ForEach(aarene, id: \.self) { aar in
                    NavigationLink {
                        ArkivAarView(aar: aar)
                    } label: {
                        let antallBilag = bilag.filter { $0.dato.aar == aar }.count
                        let sumInntekter = inntekter.filter { $0.dato.aar == aar }.reduce(0) { $0 + $1.belop }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(aar))
                                    .font(.tittel(.title3))
                                Text("\(antallBilag) bilag · \(sumInntekter.kr) i inntekter")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if Arkiv.erAktivt(aar) {
                                Text("I bruk")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.temaAksentMyk, in: Capsule())
                            }
                        }
                    }
                }
            } footer: {
                Text("Bilag skal oppbevares i fem år etter at regnskapsåret er slutt. Appen sletter aldri noe av seg selv. Når et år er ferdig, er det lurt å lagre det i Filer eller iCloud Drive også.")
            }
        }
        .temaBakgrunn()
        .navigationTitle("Arkiv")
    }
}

/// Alt fra ett år: tallene, bilagene og inntektene, og eksport.
struct ArkivAarView: View {
    let aar: Int

    @Query(sort: \Bilag.dato, order: .reverse) private var alleBilag: [Bilag]
    @Query(sort: \Inntekt.dato, order: .reverse) private var alleInntekter: [Inntekt]
    @Query private var driftsmidler: [Driftsmiddel]
    @Query private var turer: [Kjoretur]
    @Query private var fakturaer: [Faktura]

    @AppStorage(Innstilling.lonn) private var lonn: Double = 0
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false
    @AppStorage(Innstilling.hjemmekontor) private var hjemmekontor = false

    @State private var mappe: ArkivMappe?
    @State private var visEksport = false
    @State private var melding: String?

    private var bilag: [Bilag] { alleBilag.filter { $0.dato.aar == aar } }
    private var inntekter: [Inntekt] { alleInntekter.filter { $0.dato.aar == aar } }

    var body: some View {
        let o = Aarsoversikt(aar: aar, bilag: alleBilag, inntekter: alleInntekter, driftsmidler: driftsmidler,
                             turer: turer, lonn: lonn, mvaRegistrert: mvaRegistrert, hjemmekontor: hjemmekontor)
        List {
            Section {
                RadVerdi("Inntekter", o.inntekter.kr)
                RadVerdi("Fradrag", "−" + o.fradrag.kr)
                RadVerdi("Overskudd", o.overskudd.kr, uthevet: true)
                RadVerdi("Beregnet skatt fra foretaket", max(0, o.skatt.ekstraSkatt).kr)
            } header: {
                Text("Resultat")
            } footer: {
                Text("Skatten er regnet ut med lønnen som står i Innstillinger nå, så for eldre år er den bare et anslag. Det som står i skatteoppgjøret ditt, er fasiten.")
            }

            Section {
                NavigationLink {
                    List {
                        BilagMaanedSeksjoner(bilag: bilag)
                    }
                    .temaBakgrunn()
                    .navigationTitle("Bilag \(String(aar))")
                } label: {
                    RadVerdi("Bilag (\(bilag.count))", bilag.reduce(0) { $0 + $1.belop }.kr)
                }
                .disabled(bilag.isEmpty)

                NavigationLink {
                    List {
                        ForEach(inntekter) { inntekt in
                            NavigationLink {
                                InntektSkjemaView(inntekt: inntekt)
                            } label: {
                                InntektRad(inntekt: inntekt)
                            }
                        }
                    }
                    .temaBakgrunn()
                    .navigationTitle("Inntekter \(String(aar))")
                } label: {
                    RadVerdi("Inntekter (\(inntekter.count))", o.inntekter.kr)
                }
                .disabled(inntekter.isEmpty)

                let mangler = bilag.filter { ($0.vedlegg ?? []).isEmpty }.count
                if mangler > 0 {
                    Label("\(mangler) bilag mangler bilde", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Innhold")
            } footer: {
                Text("Oppbevares til og med 31.12.\(String(Arkiv.oppbevaresTil(aar))).")
            }

            Section {
                Button {
                    var pdfer: [String: Data] = [:]
                    for f in fakturaer where f.nummer > 0 && f.fakturadato.aar == aar {
                        pdfer[FakturaPDF.filnavn(for: f)] = FakturaPDF.data(for: f)
                    }
                    mappe = ArkivMappe(aar: aar, bilag: bilag, alleBilag: alleBilag, inntekter: alleInntekter,
                                       mvaRegistrert: mvaRegistrert, fakturaPDFer: pdfer)
                    visEksport = true
                } label: {
                    Label("Lagre året i Filer (regneark og bilder)", systemImage: "folder.badge.plus")
                }
                ShareLink(item: Eksport.csvFil(aar: aar, bilag: alleBilag, inntekter: alleInntekter, mvaRegistrert: mvaRegistrert),
                          preview: SharePreview("Regnskap \(String(aar)).csv")) {
                    Label("Del bare regnearket (CSV)", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Eksport")
            } footer: {
                Text("Lager en mappe med regnearket, alle kvitteringsbildene og fakturaene, navngitt med dato og tittel. Lagre den for eksempel i iCloud Drive, så har du en kopi utenfor appen.")
            }
        }
        .temaBakgrunn()
        .navigationTitle(String(aar))
        .fileExporter(isPresented: $visEksport, document: mappe, contentType: .folder,
                      defaultFilename: "Tillerflaten Digital \(aar)") { resultat in
            switch resultat {
            case .success: melding = "Mappen for \(aar) er lagret."
            case .failure(let feil): melding = "Kunne ikke lagre: \(feil.localizedDescription)"
            }
            mappe = nil
        }
        .alert("Arkiv", isPresented: Binding(get: { melding != nil }, set: { if !$0 { melding = nil } })) {
            Button("OK") {}
        } message: {
            Text(melding ?? "")
        }
    }
}

/// En mappe med regnearket og alle bildene for ett år, som kan lagres i Filer.
struct ArkivMappe: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    private let filer: [String: Data]

    init(aar: Int, bilag: [Bilag], alleBilag: [Bilag], inntekter: [Inntekt], mvaRegistrert: Bool,
         fakturaPDFer: [String: Data] = [:]) {
        var filer: [String: Data] = [:]
        for (navn, data) in fakturaPDFer {
            filer["Fakturaer/" + navn] = data
        }
        let csv = "\u{FEFF}" + Eksport.csv(aar: aar, bilag: alleBilag, inntekter: inntekter, mvaRegistrert: mvaRegistrert)
        filer["Regnskap \(aar).csv"] = Data(csv.utf8)

        func leggTil(_ navn: String, _ data: Data) {
            var kandidat = navn + ".jpg"
            var nr = 2
            while filer["Bilag/" + kandidat] != nil {
                kandidat = "\(navn) (\(nr)).jpg"
                nr += 1
            }
            filer["Bilag/" + kandidat] = data
        }
        for b in bilag {
            let navn = Arkiv.filnavn(dato: b.dato, tittel: b.tittel.isEmpty ? b.kategori.navn : b.tittel)
            for v in b.sorterteVedlegg {
                if let data = v.data { leggTil(navn, data) }
            }
        }
        for i in inntekter where i.dato.aar == aar {
            if let data = i.bilde {
                leggTil(Arkiv.filnavn(dato: i.dato, tittel: "Inntekt " + i.kilde), data)
            }
        }
        self.filer = filer
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let rot = FileWrapper(directoryWithFileWrappers: [:])
        var mapper: [String: FileWrapper] = [:]
        for (sti, data) in filer {
            let deler = sti.split(separator: "/", maxSplits: 1).map(String.init)
            if deler.count == 2 {
                let mappe = mapper[deler[0]] ?? { () -> FileWrapper in
                    let ny = FileWrapper(directoryWithFileWrappers: [:])
                    ny.preferredFilename = deler[0]
                    return ny
                }()
                mappe.addRegularFile(withContents: data, preferredFilename: deler[1])
                mapper[deler[0]] = mappe
            } else {
                rot.addRegularFile(withContents: data, preferredFilename: sti)
            }
        }
        for mappe in mapper.values {
            rot.addFileWrapper(mappe)
        }
        return rot
    }
}

/// Bilag gruppert per måned, nyeste først. Brukes både i Bilag-fanen og i arkivet.
struct BilagMaanedSeksjoner: View {
    @Environment(\.modelContext) private var context
    let bilag: [Bilag]

    private var maaneder: [(tittel: String, bilag: [Bilag])] {
        let cal = Frister.kalender
        let grupper = Dictionary(grouping: bilag) { cal.dateInterval(of: .month, for: $0.dato)?.start ?? $0.dato }
        return grupper.keys.sorted(by: >).map { start in
            (tittel: start.formatted(.dateTime.month(.wide).year()).capitalized,
             bilag: (grupper[start] ?? []).sorted { $0.dato > $1.dato })
        }
    }

    var body: some View {
        ForEach(maaneder, id: \.tittel) { maaned in
            Section {
                ForEach(maaned.bilag) { b in
                    NavigationLink {
                        BilagSkjemaView(bilag: b)
                    } label: {
                        BilagRad(bilag: b)
                    }
                }
                .onDelete { indekser in
                    for i in indekser {
                        let b = maaned.bilag[i]
                        Varsler.fjernRegning(b)
                        Kalender.fjern(regning: b)
                        context.delete(b)
                    }
                }
            } header: {
                HStack {
                    Text(maaned.tittel)
                    Spacer()
                    Text(maaned.bilag.reduce(0) { $0 + $1.belop }.kr)
                }
            }
        }
    }
}

struct InntektRad: View {
    let inntekt: Inntekt

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(inntekt.kilde)
                Text(inntekt.dato.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(inntekt.belop.kr)
                .monospacedDigit()
        }
    }
}

/// Lenke nederst i Bilag og Inntekter til eldre år.
struct ArkivLenke: View {
    let antall: Int
    let hva: String

    var body: some View {
        Section {
            NavigationLink {
                ArkivView()
            } label: {
                Label("\(antall) \(hva) fra tidligere år ligger i Arkiv", systemImage: "archivebox")
            }
        }
    }
}
