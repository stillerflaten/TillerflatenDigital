import SwiftUI
import SwiftData

@main
struct RegnskapApp: App {
    let container = Lagring.lagContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: "nb_NO"))
                .task { Lagring.flyttGamleBilder(container.mainContext) }
        }
        .modelContainer(container)
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Oversikt", systemImage: "chart.bar.doc.horizontal") {
                OversiktView()
            }
            Tab("Bilag", systemImage: "doc.text.viewfinder") {
                BilagListeView()
            }
            Tab("Inntekter", systemImage: "banknote") {
                InntekterView()
            }
            Tab("Kalkulatorer", systemImage: "function") {
                KalkulatorerView()
            }
            Tab("Frister", systemImage: "calendar.badge.clock") {
                FristerView()
            }
        }
    }
}
