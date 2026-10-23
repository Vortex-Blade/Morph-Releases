# Morph 1.0 RC1 — automatische DMG

Voer op je Mac uit: `bash build-all-in-one.sh`.

Het script bouwt `dist/Morph.app`, bundelt de lokaal beschikbare FFmpeg-, qpdf- en LibreOffice-tools, maakt `dist/Morph-1.0-RC1.dmg` met een Applications-snelkoppeling en verifieert het schijfkopiebestand.

**Bouwvereisten:** Swift/Xcode Command Line Tools, Python 3, FFmpeg, qpdf en LibreOffice moeten op de bouw-Mac beschikbaar zijn. Dit script installeert ontbrekende vereisten **niet** automatisch.

**Distributie:** de DMG is ad-hoc ondertekend, niet Developer-ID-ondertekend of door Apple genotariseerd. Controleer de app en meegeleverde tools op een schone Mac voordat je hem verspreidt.
