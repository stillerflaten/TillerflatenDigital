import SwiftUI
import SwiftData

@main
struct RegnskapApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: "nb_NO"))
        }
        .modelContainer(for: [Bilag.self, Inntekt.self, Driftsmiddel.self, Kjoretur.self])
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
