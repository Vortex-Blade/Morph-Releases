# Morph v0.3 — Morph Quick (macOS)

## Installeren

Open Terminal in deze map en voer uit:

```bash
bash make-app.sh
open dist/Morph.app
```

**Belangrijk:** sluit een eerdere Morph-versie volledig af voordat je v0.3 start, anders kan de globale sneltoets door de oude versie worden geregistreerd.

## Morph Quick

1. Selecteer een ondersteund bestand in Finder.
2. Druk **Option + Command + M**.
3. Sta indien gevraagd Finder-automatisering toe.
4. Klik op een formaat in het zwevende conversiewiel.
5. Het resultaat wordt naast het origineel opgeslagen en in Finder getoond.

Morph Quick ondersteunt de uitvoerformaten van de bestaande conversie-engine. FFmpeg en LibreOffice moeten afzonderlijk geïnstalleerd zijn voor respectievelijk media en documenten. Niet elke combinatie van invoer en uitvoer is geldig.

**Nog niet beschikbaar:** het wiel openen door tijdens een Finder-sleepactie Shift ingedrukt te houden, en het bestand op een segment droppen. macOS biedt hiervoor geen eenvoudige openbare cross-app drag-hook; dit vereist aparte technische validatie. Deze versie gebruikt daarom een betrouwbare Finder-selectie en sneltoets.

Dit project is op Linux samengesteld en kan hier niet tegen macOS SwiftUI worden gecompileerd. Bouw en test het op je Mac. Deel eventuele compilerfouten met bestandsnaam en regelnummer.

## Shift + slepen (experimenteel)

Morph observeert nu globale Shift + sleepbewegingen wanneer Finder actief is.
Het conversiewiel opent met de geselecteerde Finder-bestanden; kies een formaat
door te **klikken**. Dit is nog geen echte drop-target-integratie.

macOS kan toestemming voor **Invoercontrole** (Input Monitoring) en
**Automatisering > Finder** vereisen. Sluit Morph volledig af en herstart
na het wijzigen van toestemmingen. Gebruik als fallback Option+Command+M.

De code is hier niet op macOS gecompileerd of getest.

## v0.4.1
Control + Shift + Finder-slepen opent het conversiewiel nabij de cursor (experimenteel). De bestanden worden uit de Finder-selectie gelezen; loslaten op een formaat werkt nog niet. De bestaande Option+Command+M-sneltoets blijft beschikbaar.

## v0.4.2 — Morph Quick automatisch sluiten

Na een volledig geslaagde conversie verdwijnt het Morph Quick-venster automatisch. Bij een fout blijft het open om de melding te tonen. De hoofdapp blijft draaien, zodat de sneltoets opnieuw werkt.

## v0.4.3 — Drop op formaat (experimenteel)

Elke formaatknop accepteert nu een standaard macOS Finder-file-drop via SwiftUI `onDrop`.
Een geslaagde drop converteert de **daadwerkelijk gedropte bestanden** en sluit het wiel
na succes; fouten houden het venster open. Klikken op een formaat blijft werken.

**Beperking:** Finder/macOS kan de actieve sleepactie annuleren wanneer Morph tijdens
het slepen een nieuw zwevend venster opent. Daarom is dit nog geen gegarandeerd
werkende Tangerine-achtige globale drag-ervaring. Test eerst of het dropdoel een
bestand ontvangt; zo niet, dan moeten we het venster/drag-architectuur herzien.
De broncode kan in deze omgeving niet met macOS SwiftUI worden gecompileerd.

## v0.4.4 — immediate modifier detection
The global monitor now listens for `flagsChanged` in addition to dragging. When Control+Shift is pressed while Finder is dragging, Morph attempts to show the wheel immediately, without waiting for key release. Finder may not hand off an already-started drag to a newly opened window; direct drop still needs real macOS testing. Accessibility/Input Monitoring permissions may be necessary.


## v0.4.5 UI update
Morph Quick has a redesigned violet neon radial interface with the purple blob icon, ring effects, hover states, and the same conversion/drop callbacks. Shift+Control detection remains experimental. Build on macOS with `bash make-app.sh`.


## v0.4.6 design
The Morph Quick wheel now uses the supplied visual reference: large circular dark purple panel, 8 evenly spaced circular drop targets, prominent top target, glowing violet rim and centered blob artwork. Only supported output formats are displayed; the exact eight shown depend on the selected file. Existing shortcut and experimental Control+Shift drag detection are unchanged.

This source package has not been compiled on macOS in this environment.

## v0.5 — Compressie

Open **Compressie** in de zijbalk. Voeg afbeeldingen, video's of PDF's toe, stel de kwaliteit in en klik op **Comprimeren**. Resultaten worden naast de originele bestanden geplaatst, met `_morph` in de naam. Alleen kleinere resultaten worden bewaard.

- Afbeeldingen: Apple ImageIO, exporteert naar JPG; transparantie wordt wit en animaties worden niet behouden.
- Video: FFmpeg vereist (`brew install ffmpeg`); H.264/AAC, mogelijk kwaliteitsverlies.
- PDF: qpdf vereist (`brew install qpdf`); verliesvrije hercompressie van streams, niet gegarandeerd veel kleiner.
- De app blijft offline; geen cloudverwerking.
- Op macOS bouwen en testen: `bash make-app.sh`. Niet op macOS gecompileerd in deze omgeving.

## Morph v0.5.1 — PDF splitsen

Ga naar **PDF-tools**, voeg één of meer PDF-bestanden toe en klik op
**PDF splitsen per pagina**. Morph schrijft elke pagina als afzonderlijke PDF
naast het originele bestand (`naam_pagina_1.pdf`, enzovoort). Bestaande
bestanden worden niet overschreven. Geen extra tools nodig: PDFKit.

Opmerking: PDF's met wachtwoordbeveiliging kunnen niet altijd worden geopend.
Deze versie is nog niet op macOS gecompileerd of getest.

## v0.6 — Aanvullende tools
- Metadata verwijderen voor **stilstaande** JPG/PNG/TIFF/HEIC/GIF via opnieuw coderen met ImageIO. Geanimeerde afbeeldingen worden geweigerd. Niet bedoeld als forensische anonimisering; controleer uitvoerbestanden zelf.
- PDF roteren (alle pagina's +90 graden) en één paginanummer verwijderen, via PDFKit.
- Video inkorten via FFmpeg (starttijd en duur in seconden; uitvoer MP4 H.264/AAC).
- ZIP uitpakken via macOS `ditto` naar een nieuwe map.
- Geschiedenis (maximaal 300 paden) lokaal opgeslagen in UserDefaults.
- Bestaande Quick-wheel, Control+Shift-detectie, compressie, PDF-splitsen en conversies blijven behouden.

**Beperkingen:** nog niet op macOS gecompileerd of end-to-end getest. Bestandsconversies kunnen afhankelijk van formaten en tools mislukken. Finder-drop tijdens een bestaande drag blijft experimenteel. Dit is geen geaudite privacytool.
