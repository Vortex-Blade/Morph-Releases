# Morph 1.1 Friends Edition (broncode)

## Verbeteringen
- Dock opnieuw aanklikken opent het hoofdvenster na sluiten. Morph Quick blijft draaien.
- DMG met Applications-snelkoppeling, automatisch gemaakt via `diskutil`.
- FFmpeg-controle gebruikt de correcte `-version`-parameter.
- Handmatige GitHub-releasecontrole voor `Vortex-Blade/Morph-Releases`.

## Build
Op macOS in de map `Morph`: `bash build-all-in-one.sh`.

## Updates: belangrijk
De knop **Controleer updates** vraagt de nieuwste publieke GitHub-release op en opent die op verzoek. **Automatisch installeren is nog niet geïmplementeerd.** Voor veilige automatische installatie met Sparkle zijn een publieke appcast, EdDSA-sleutels, Sparkle-integratie en tests op een Mac nodig. De repository `Vortex-Blade/Morph-Releases` moet nog bestaan en releases bevatten.

## Distributie
Deze build is ad-hoc ondertekend, niet Developer-ID ondertekend of genotariseerd. macOS kan op andere Macs een Gatekeeper-waarschuwing geven. Test altijd eerst met vrienden.
