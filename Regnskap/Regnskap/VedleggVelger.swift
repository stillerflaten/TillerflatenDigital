import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

/// Flere bilder på ett bilag: skann flere sider, velg flere bilder, se og slett dem.
struct VedleggVelger: View {
    let bilag: Bilag

    @State private var valgteFoto: [PhotosPickerItem] = []
    @State private var visSkanner = false
    @State private var visStortBilde: BildeIndeks?
    @State private var laster = false

    private var vedlegg: [Vedlegg] { bilag.sorterteVedlegg }

    var body: some View {
        if !vedlegg.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(vedlegg.enumerated()), id: \.element.uuid) { par in
                        let v = par.element
                        if let data = v.data, let bilde = UIImage(data: data) {
                            Button {
                                visStortBilde = BildeIndeks(id: par.offset)
                            } label: {
                                Image(uiImage: bilde)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 110, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Slett bilde", systemImage: "trash", role: .destructive) {
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
                StortBildeView(bilder: vedlegg.compactMap { $0.data.flatMap(UIImage.init(data:)) }, valgt: start.id)
            }

            Text(vedlegg.count == 1
                 ? "1 bilde. Trykk for å se det, hold inne for å slette."
                 : "\(vedlegg.count) bilder. Trykk for å se dem, hold inne for å slette.")
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
                    leggTil(sider.compactMap { Bildeverktoy.komprimer($0) })
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
                leggTil(data)
                valgteFoto = []
                laster = false
            }
        }
    }

    private func leggTil(_ bilder: [Data]) {
        let start = (vedlegg.map(\.nr).max() ?? -1) + 1
        let nye = bilder.enumerated().map { Vedlegg(data: $1, nr: start + $0) }
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
