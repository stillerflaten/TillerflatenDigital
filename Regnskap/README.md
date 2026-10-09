# Regnskap – Tillerflaten Digital

En iPhone-app (SwiftUI + SwiftData) som hjelper med regnskapet i enkeltpersonforetaket ved siden av fast jobb.

All data lagres bare lokalt på telefonen. Ingenting sendes noe sted.

## Hva appen gjør

| Fane | Innhold |
|---|---|
| **Oversikt** | Årets inntekter, fradrag og overskudd, og hvor mye du bør sette av til skatt. Viser også hvor nær du er mva-grensen, ubetalte regninger og neste frist. Eksport til regneark (CSV). |
| **Bilag** | Kvitteringer og regninger med ett eller flere bilder (skann flere sider med kameraet eller velg flere bilder), kategori, mva og hvor stor del som brukes i foretaket. Regninger får varsel dagen før forfall. |
| **Inntekter** | Utbetalinger fra App Store (og andre inntekter), med anslag på hvor mye av hver utbetaling du bør sette av. |
| **Kalkulatorer** | Skatt på overskuddet oppå lønn, avskrivning av utstyr (direkte fradrag eller saldogruppe a/d), kjørelogg, forklaring av mva for App Store-utviklere og en sjekkliste for nytt ENK. |
| **Frister** | Forskuddsskatt, skattemelding og (hvis mva-registrert) mva-terminer, med varsler. |

## Satser

Alle satser ligger i `Regnskap/Satser.swift`. De er hentet fra
[Skattesatser 2026 (regjeringen.no)](https://www.regjeringen.no/no/tema/okonomi-og-budsjett/skatter-og-avgifter/skattesatser-2026/id3121978/)
og [Skatteetaten](https://www.skatteetaten.no/person/skatt/skattekort/forskuddsskatt/) i oktober 2026.

Kilometersatsen (3,50 kr/km) og hjemmekontor-sjablongen (1 850 kr) bør dobbeltsjekkes hos Skatteetaten.

Når 2027-satsene er vedtatt (desember), legges de inn som `aar2027` i samme fil.

Tallene er estimater og erstatter ikke Skatteetaten eller en regnskapsfører.

## Slik åpner og kjører du appen

1. Åpne **GitHub Desktop**.
2. Velg repoet **TillerflatenDigital** øverst til venstre.
3. Klikk **Fetch origin**.
4. Klikk på **Current Branch** og velg `claude/regnskapsapp-4hc1kn`.
5. Velg **Repository → Show in Finder**.
6. Gå inn i mappen `Regnskap` og dobbeltklikk på `Regnskap.xcodeproj`. Xcode åpner seg.
7. Klikk på det blå **Regnskap**-ikonet øverst i venstre kolonne, velg target **Regnskap**, fanen **Signing & Capabilities**, og sjekk at **Team** er ditt (samme som i HockeySub).
8. Velg iPhone-en din (eller en simulator) øverst i Xcode, og trykk **▶︎** (eller ⌘R).

Testene kjører du med **⌘U**. De sjekker at skatte-, avskrivnings- og fristberegningene gir riktige tall.
