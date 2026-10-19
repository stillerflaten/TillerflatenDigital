import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import PDFKit
import QuickLook
import UniformTypeIdentifiers

extension Vedlegg {
    /// Miniatyrene huskes, så listen ikke leser og tegner filene på nytt hver gang den oppdateres.
    private static let miniatyrer = NSCache<NSString, UIImage>()

    /// Bildet, eller første side av PDF-en, til å vise som miniatyr.
    func miniatyr(storrelse: CGSize = CGSize(width: 220, height: 300)) -> UIImage? {
        let nokkel = "\(uuid.uuidString)-\(Int(storrelse.width))x\(Int(storrelse.height))" as NSString
        if let lagret = Self.miniatyrer.object(forKey: nokkel) { return lagret }
        guard let data else { return nil }
        let bilde: UIImage?
        if erPdf {
            bilde = PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: storrelse, for: .mediaBox)
        } else {
            bilde = UIImage(data: data)
        }
        if let bilde { Self.miniatyrer.setObject(bilde, forKey: nokkel) }
        return bilde
    }

    /// Lagrer vedlegget midlertidig, så det kan åpnes og deles.
    func midlertidigFil() -> URL? {
        guard let data else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kvittering-\(uuid.uuidString)")
            .appendingPathExtension(filtype)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// Flere vedlegg på ett bilag: skann flere sider, velg bilder eller PDF-er, se og slett dem.
struct VedleggVelger: View {
    let bilag: Bilag

    @State private var valgteFoto: [PhotosPickerItem] = []
    @State private var visSkanner = false
    @State private var visFilvelger = false
    @State private var visStortBilde: BildeIndeks?
    @State private var forhandsvis: URL?
    @State private var feil: String?
    @State private var laster = false

    private var vedlegg: [Vedlegg] { bilag.sorterteVedlegg }
    /// Bildene som kan vises i fullskjerm, i samme rekkefølge som i StortBildeView.
    private var bilder: [(uuid: UUID, bilde: UIImage)] {
        vedlegg.compactMap { v in
            guard !v.erPdf, let bilde = v.data.flatMap(UIImage.init(data:)) else { return nil }
            return (v.uuid, bilde)
        }
    }

    var body: some View {
        if !vedlegg.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(vedlegg, id: \.uuid) { v in
                        if let bilde = v.miniatyr() {
                            Button {
                                apne(v)
                            } label: {
                                Image(uiImage: bilde)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 110, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .bottomLeading) {
                                        if v.erPdf {
                                            Text("PDF")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.red.opacity(0.85), in: Capsule())
                                                .padding(5)
                                        }
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3))
                                    }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(v.erPdf ? "Slett PDF" : "Slett bilde", systemImage: "trash", role: .destructive) {
                                    fjern(v)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .fullScreenCover(item: $visStortBilde) { start in
                StortBildeView(bilder: bilder.map(\.bilde), valgt: start.id)
            }

            Text(vedlegg.count == 1
                 ? "1 vedlegg. Trykk for å se det, hold inne for å slette."
                 : "\(vedlegg.count) vedlegg. Trykk for å se dem, hold inne for å slette.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if VNDocumentCameraViewController.isSupported {
            Button {
                visSkanner = true
            } label: {
                Label("Skann kvittering (én eller flere sider)", systemImage: "doc.viewfinder")
            }
            .fullScreenCover(isPresented: $visSkanner) {
                DokumentSkanner { sider in
                    leggTil(sider.compactMap { Bildeverktoy.komprimer($0) }.map { ($0, "jpg") })
                }
                .ignoresSafeArea()
            }
        }

        PhotosPicker(selection: $valgteFoto, maxSelectionCount: 20, matching: .images) {
            HStack {
                Label("Velg bilder eller skjermbilder", systemImage: "photo.on.rectangle")
                if laster {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .onChange(of: valgteFoto) { _, nye in
            guard !nye.isEmpty else { return }
            laster = true
            Task {
                var data: [Data] = []
                for item in nye {
                    if let raa = try? await item.loadTransferable(type: Data.self),
                       let bilde = UIImage(data: raa),
                       let komprimert = Bildeverktoy.komprimer(bilde) {
                        data.append(komprimert)
                    }
                }
                leggTil(data.map { ($0, "jpg") })
                valgteFoto = []
                laster = false
            }
        }

        Button {
            visFilvelger = true
        } label: {
            Label("Velg PDF eller fil", systemImage: "doc.richtext")
        }
        .quickLookPreview($forhandsvis)
        .fileImporter(isPresented: $visFilvelger, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { svar in
            guard case .success(let urler) = svar else { return }
            var nye: [(Data, String)] = []
            var feilet: [String] = []
            for url in urler {
                let tilgang = url.startAccessingSecurityScopedResource()
                defer { if tilgang { url.stopAccessingSecurityScopedResource() } }
                guard let raa = try? Data(contentsOf: url) else {
                    feilet.append(url.lastPathComponent)
                    continue
                }
                if PDFDocument(data: raa) != nil {
                    nye.append((raa, "pdf"))
                } else if let bilde = UIImage(data: raa), let jpg = Bildeverktoy.komprimer(bilde) {
                    nye.append((jpg, "jpg"))
                } else {
                    feilet.append(url.lastPathComponent)
                }
            }
            leggTil(nye)
            if !feilet.isEmpty {
                feil = "Kunne ikke lese \(feilet.map { "«\($0)»" }.joined(separator: ", ")). Ligger filen i iCloud Drive, kan du åpne den i Filer-appen først så den lastes ned."
            }
        }
        .alert("Vedlegg", isPresented: Binding(get: { feil != nil }, set: { if !$0 { feil = nil } })) {
            Button("OK") { feil = nil }
        } message: {
            Text(feil ?? "")
        }
    }

    private func apne(_ v: Vedlegg) {
        if v.erPdf {
            if let url = v.midlertidigFil() {
                forhandsvis = url
            } else {
                feil = "Fant ikke filen. Den er kanskje ikke ferdig synkronisert fra iCloud ennå."
            }
        } else if let i = bilder.firstIndex(where: { $0.uuid == v.uuid }) {
            visStortBilde = BildeIndeks(id: i)
        }
    }

    /// Hvert element er filens innhold og filtype («jpg» eller «pdf»).
    private func leggTil(_ filer: [(Data, String)]) {
        let start = (vedlegg.map(\.nr).max() ?? -1) + 1
        let nye = filer.enumerated().map { Vedlegg(data: $1.0, nr: start + $0, filtype: $1.1) }
        for v in nye {
            bilag.modelContext?.insert(v)
        }
        bilag.vedlegg = (bilag.vedlegg ?? []) + nye
    }

    private func fjern(_ v: Vedlegg) {
        bilag.vedlegg?.removeAll { $0.uuid == v.uuid }
        bilag.modelContext?.delete(v)
    }
}

struct BildeIndeks: Identifiable {
    let id: Int
}
