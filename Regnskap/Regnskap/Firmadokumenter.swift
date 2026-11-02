import SwiftUI
import SwiftData

/// Viktige papirer for hele foretaket, f.eks. vedtaket om bierverv, registreringen i Brønnøysund
/// og avtalen med Apple. Åpnes fra Oversikt.
struct FirmadokumenterView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Dokument> { $0.erFirmadokument }, sort: \Dokument.navn)
    private var dokumenter: [Dokument]

    @State private var sok = ""
    @State private var endre: Dokument?
    @State private var slett: Dokument?

    private var utvalg: [Dokument] {
        let s = sok.trimmet
        guard !s.isEmpty else { return dokumenter }
        return dokumenter.filter { $0.navn.localizedCaseInsensitiveContains(s) || $0.notat.localizedCaseInsensitiveContains(s) }
    }

    var body: some View {
        List {
            if dokumenter.isEmpty {
                ContentUnavailableView {
                    Label("Ingen firmadokumenter", systemImage: "folder")
                } description: {
                    Text("Legg inn viktige papirer for foretaket, f.eks. vedtaket om bierverv, registreringen i Brønnøysund, mva-registreringen og avtalen med Apple.")
                }
            }

            Section {
                ForEach(utvalg) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        DokumentRad(dokument: d)
                        let husk = (d.huskepunkter ?? []).filter { !$0.ferdig }
                        if !husk.isEmpty {
                            Label(husk.map(\.tittel).joined(separator: ", "), systemImage: "bell")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Slett", systemImage: "trash", role: .destructive) { slett = d }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Endre", systemImage: "pencil") { endre = d }
                            .tint(Color.accentColor)
                    }
                    .contextMenu {
                        Button("Endre navn og notat", systemImage: "pencil") { endre = d }
                        Button("Slett", systemImage: "trash", role: .destructive) { slett = d }
                    }
                }

                DokumentLeggTilMeny { d in
                    d.erFirmadokument = true
                    context.insert(d)
                    try? context.save()
                    endre = d
                }
            } footer: {
                Text("Trykk for å åpne og dele. Sveip til høyre for å endre navn og notat, og til venstre for å slette. Dokumentene synkes via iCloud og er med i sikkerhetskopien. Du kan også legge dem ved huskepunkter under Frister.")
            }
        }
        .searchable(text: $sok, prompt: "Søk i dokumenter")
        .temaBakgrunn()
        .navigationTitle("Firmadokumenter")
        .sheet(item: $endre) { d in
            NavigationStack {
                DokumentSkjemaView(dokument: d)
            }
        }
        .confirmationDialog("Slette «\(slett?.navn ?? "")»?", isPresented: Binding(get: { slett != nil }, set: { if !$0 { slett = nil } }),
                            titleVisibility: .visible) {
            Button("Slett", role: .destructive) {
                if let d = slett {
                    context.delete(d)
                    try? context.save()
                }
                slett = nil
            }
        } message: {
            Text("Dokumentet fjernes også fra huskepunktene det er lagt ved.")
        }
    }
}

/// Endre navn og notat på et dokument.
struct DokumentSkjemaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var dokument: Dokument

    var body: some View {
        Form {
            Section {
                TextField("Navn", text: $dokument.navn)
                TextField("Notat (valgfritt)", text: $dokument.notat, axis: .vertical)
            } footer: {
                Text("Gi dokumentet et navn du kjenner igjen, f.eks. «Vedtak om bierverv 2026–2028».")
            }
            Section {
                DokumentRad(dokument: dokument)
            }
        }
        .tastaturFerdigKnapp()
        .temaBakgrunn()
        .navigationTitle("Dokument")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Ferdig") {
                    if dokument.navn.trimmet.isEmpty { dokument.navn = "Dokument" }
                    try? context.save()
                    dismiss()
                }
            }
        }
    }
}

/// Dokumentene som er lagt ved et huskepunkt. Nye dokumenter blir også firmadokumenter.
/// Arkene (velg dokument, endre navn) eies av skjemaet rundt, fordi et ark som henger på en
/// `Section` i et `Form` blir lagt på hver rad, og da lukker skjemaet seg når du velger noe.
struct HuskepunktDokumentSeksjon: View {
    @Environment(\.modelContext) private var context
    @Bindable var huskepunkt: Huskepunkt
    @Binding var visVelger: Bool
    @Binding var endre: Dokument?

    private var vedlagt: [Dokument] { (huskepunkt.dokumenter ?? []).sorted { $0.navn < $1.navn } }

    var body: some View {
        Section {
            ForEach(vedlagt) { d in
                DokumentRad(dokument: d)
                    .swipeActions(edge: .trailing) {
                        Button("Fjern", systemImage: "minus.circle", role: .destructive) { fjern(d) }
                    }
            }

            DokumentLeggTilMeny(tittel: "Legg ved nytt dokument") { d in
                d.erFirmadokument = true
                context.insert(d)
                huskepunkt.dokumenter = (huskepunkt.dokumenter ?? []) + [d]
                try? context.save()
                endre = d
            }

            Button {
                visVelger = true
            } label: {
                Label("Velg blant firmadokumentene", systemImage: "folder")
            }
        } header: {
            Text("Dokumenter")
        } footer: {
            Text("Trykk for å åpne. Sveip til venstre for å fjerne et dokument fra huskepunktet. Dokumentet blir liggende under Firmadokumenter.")
        }
    }

    private func fjern(_ d: Dokument) {
        huskepunkt.dokumenter?.removeAll { $0.uuid == d.uuid }
        try? context.save()
    }
}

/// Liste over firmadokumenter å velge fra.
struct VelgFirmadokumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Dokument> { $0.erFirmadokument }, sort: \Dokument.navn)
    private var dokumenter: [Dokument]

    let valgt: Set<UUID>
    let velg: (Dokument) -> Void

    private var ledige: [Dokument] { dokumenter.filter { !valgt.contains($0.uuid) } }

    var body: some View {
        List {
            if ledige.isEmpty {
                ContentUnavailableView("Ingen flere dokumenter", systemImage: "folder",
                                       description: Text("Legg inn dokumenter under Oversikt → Firmadokumenter, eller legg ved et nytt dokument direkte på huskepunktet."))
            }
            ForEach(ledige) { d in
                Button {
                    velg(d)
                    dismiss()
                } label: {
                    Label(d.navn, systemImage: d.ikon)
                }
                .tint(.primary)
            }
        }
        .temaBakgrunn()
        .navigationTitle("Velg dokument")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
        }
    }
}
