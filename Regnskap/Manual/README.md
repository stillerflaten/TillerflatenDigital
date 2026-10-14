# Brukermanual

Kilden til brukermanualen i appen. Endre `Brukermanual-Regnskap.html` og lag PDF-en på nytt:

```
node lag-pdf.js "$PWD/Brukermanual-Regnskap.html" "$PWD/../Regnskap/Brukermanual-Regnskap.pdf"
```

Krever Node med Playwright og Chromium. PDF-en i `Regnskap/Regnskap/` følger med i appen og åpnes fra Oversikt (spørsmålstegnet) og Innstillinger › Brukermanual.
