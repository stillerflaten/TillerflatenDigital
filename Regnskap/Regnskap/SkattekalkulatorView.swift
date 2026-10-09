import SwiftUI
import SwiftData

struct KalkulatorerView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SkattekalkulatorView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Skatt på App Store-inntekt")
                                Text("Hvor mye bør jeg sette av?").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "percent") }
                    }
                    NavigationLink {
                        AvskrivningView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Avskrivning av utstyr")
                                Text("Hvor mye kan jeg trekke fra for Mac, iPhone osv.?").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "laptopcomputer") }
                    }
                    NavigationLink {
                        KjoreloggView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Kjørelogg")
                                Text("Fradrag for kjøring med egen bil").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "car") }
                    }
                    NavigationLink {
                        MvaView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Mva og App Store")
                                Text("Når må jeg registrere meg?").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "building.columns") }
                    }
                }
                Section {
                    NavigationLink {
                        SjekklisteView()
                    } label: {
                        Label("Sjekkliste for nytt enkeltpersonforetak", systemImage: "checklist")
                    }
                }
            }
            .navigationTitle("Kalkulatorer")
        }
    }
}

struct SkattekalkulatorView: View {
    @Query private var bilag: [Bilag]
    @Query private var inntekter: [Inntekt]
    @Query private var driftsmidler: [Driftsmiddel]
    @Query private var turer: [Kjoretur]

    @AppStorage(Innstilling.lonn) private var lonn: Double = 0
    @AppStorage(Innstilling.mvaRegistrert) private var mvaRegistrert = false
    @AppStorage(Innstilling.hjemmekontor) private var hjemmekontor = false

    @State private var inntekt: Double = 0
    @State private var kostnader: Double = 0
    @State private var hentet = false

    private let aar = Date.now.aar

    private var satser: Skattesatser { .gjeldende(for: aar) }
    private var overskudd: Double { inntekt - kostnader }
    private var skatt: EnkSkatt { EnkSkatt(lonn: lonn, overskudd: overskudd, satser: satser) }

    var body: some View {
        let s = skatt
        let terminer = Frister.gjenstaendeForskuddsterminer()
        Form {
            Section {
                BelopFelt("Lønn (brutto)", belop: $lonn)
                BelopFelt("Inntekt i foretaket", belop: $inntekt)
                BelopFelt("Kostnader og fradrag", belop: $kostnader)
                Button("Hent tallene mine for \(String(aar))") { hentTall() }
            } header: {
                Text("Tall for \(String(aar))")
            } footer: {
                Text("Inntekt er det Apple har betalt ut. Kostnader er alt du kan trekke fra: utstyr, abonnementer, avskrivning, kjøring osv.")
            }

            Section("Resultat") {
                RadVerdi("Overskudd", overskudd.kr)
                RadVerdi("Skatt på alminnelig inntekt (22 %)", s.ekstraInntektsskatt.kr)
                RadVerdi("Trygdeavgift (\((satser.trygdeavgiftNaering).prosent))", s.ekstraTrygdeavgift.kr)
                RadVerdi("Trinnskatt", s.ekstraTrinnskatt.kr)
                RadVerdi("Ekstra skatt totalt", max(0, s.ekstraSkatt).kr, uthevet: true)
                if overskudd > 0 {
                    RadVerdi("Andel av overskuddet", s.andel(av: overskudd).prosent)
                    RadVerdi("Skatt på neste 1 000 kr", (s.marginalsats * 1_000).kr)
                }
            }

            if overskudd > 0 && terminer > 0 {
                Section {
                    RadVerdi("Per termin (\(terminer) igjen i år)", (max(0, s.ekstraSkatt) / Double(terminer)).kr, uthevet: true)
                    Link(destination: Kilder.forskuddsskatt) {
                        Label("Endre forskuddsskatten på skatteetaten.no", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("Forskuddsskatt")
                } footer: {
                    Text("Betaler du for lite i forskudd, får du restskatt med renter neste år. Logg inn på skatteetaten.no, velg «Endre skattekort/forskuddsskatt» og legg inn forventet overskudd fra foretaket.")
                }
            }

            Section {
                Text("Overskuddet fra foretaket kommer oppå lønnen din. Derfor skattes det med det som er din marginalskatt:")
                Text("• 22 % skatt på alminnelig inntekt\n• \(satser.trygdeavgiftNaering.prosent) trygdeavgift (høyere enn de \(satser.trygdeavgiftLonn.prosent) du betaler av lønn)\n• trinnskatt, som avhenger av samlet lønn + overskudd")
                Text("Personfradrag og minstefradrag er allerede brukt opp på lønnen, så de gir ikke noe ekstra her.")
                Link("Skattesatser \(String(satser.aar)) (regjeringen.no)", destination: Kilder.skattesatser)
                Link("Skatteetatens skattekalkulator", destination: Kilder.skattekalkulator)
            } header: {
                Text("Slik regnes det")
            } footer: {
                Text("Dette er et estimat. Renter, gjeld, formue, pendlerfradrag og andre forhold er ikke med. Sjekk alltid mot Skatteetaten.")
            }
        }
        .tastaturFerdigKnapp()
        .navigationTitle("Skatt")
        .onAppear {
            if !hentet { hentTall() }
        }
    }

    private func hentTall() {
        hentet = true
        let o = Aarsoversikt(aar: aar, bilag: bilag, inntekter: inntekter, driftsmidler: driftsmidler, turer: turer,
                             lonn: lonn, mvaRegistrert: mvaRegistrert, hjemmekontor: hjemmekontor)
        inntekt = o.inntekter
        kostnader = o.fradrag
    }
}
