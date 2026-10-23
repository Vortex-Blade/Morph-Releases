# Morph v0.7 — All-in-One build

Dit pakket bevat **broncode en een bouwscript**, nog geen volledig verpakte `.app`.
Een zelfstandige macOS-app kan alleen worden gemaakt op een Mac waarop de benodigde
Apple Silicon builds van de tools beschikbaar zijn. De **eindgebruiker** hoeft deze
programma's niet apart te installeren.

## Eenmalig op de bouw-Mac

1. Installeer Xcode Command Line Tools: `xcode-select --install`.
2. Installeer FFmpeg en qpdf voor het bouwen: `brew install ffmpeg qpdf`.
3. Installeer LibreOffice in `/Applications/LibreOffice.app`.
4. Start `bash build-all-in-one.sh` vanuit de `Morph`-map.
5. Het resultaat staat in `dist/Morph.app`.

Een alternatieve locatie voor LibreOffice kan met `MORPH_LIBREOFFICE_APP=/pad/LibreOffice.app`.

Het script bundelt FFmpeg en qpdf plus hun niet-systeem-dylibs, en kopieert de
volledige LibreOffice-app naar `Contents/Helpers/LibreOffice.app`. Morph zoekt
eerst in de eigen app-bundel en valt alleen bij ontwikkelbuilds terug op de
lokale installatie.

## Verificatie

- Bouw en test op Apple Silicon macOS 13+.
- Test video-, audio-, PDF- en documentconversies op een **schone Mac zonder Homebrew**.
- Controleer met `otool -L` dat alle niet-systeemafhankelijkheden ingepakt zijn.
- Voor verspreiding buiten de eigen Mac: onderteken alle componenten met een
  Developer ID, stel hardened runtime/entitlements correct in, notariseer de app
  en maak vervolgens een DMG. Ad-hoc signing uit het script is **geen notarization**.
- Controleer de distributielicenties en lever de benodigde licentieteksten en
  broncode-aanbiedingen mee (met name FFmpeg-codecs en LibreOffice).

**Status:** scripts zijn in Linux voorbereid, maar niet op macOS gecompileerd of
end-to-end gevalideerd. Sommige Homebrew builds gebruiken complexere `@rpath`
configuraties; als de bundelstap faalt, moeten die paden op de bouw-Mac worden
gecontroleerd. LibreOffice kan bij sommige macOS-versies extra signing-aanpassingen
vereisen.
