# SD Clone

App per macOS per salvare, ripristinare e clonare schede SD (pensata per Raspberry Pi), con interfaccia SwiftUI
e un comando da terminale (`sdclone`) che usa lo stesso motore.

> Stato: **fase 3** – app SwiftUI funzionante (backup, ripristino, archivio, compressione `.xz`) sopra il motore `SDCore`.
> Backup e ripristino su SD vera sono stati provati dal terminale; helper privilegiato, riduzione tipo PiShrink, firma e release sono in arrivo.

## L'app

```bash
scripts/build-app.sh            # crea "build/SD Clone.app" (firma ad-hoc, per questo Mac)
open "build/SD Clone.app"
```

- **Backup:** sceglie la scheda (con le sue partizioni), la cartella e il nome; copia fino alla fine dell'ultima
  partizione e registra lo SHA256 accanto all'immagine. Formato `.img` oppure **`.img.xz`** (compresso, di solito
  3-5 volte piu' piccolo: comodo da caricare su Google Drive). Il menu «Vai a» propone Documenti, Scrivania e le
  cartelle di Google Drive sincronizzate sul Mac.
- **Ottimizza:** prepara un'immagine da distribuire (es. la golden). **Riduci** porta la partizione Linux al minimo
  (stile PiShrink), **Togli le cronologie** cancella `.bash_history` & co. da `/root` e `/home`, **Comprimi** produce
  il `.img.xz`. Lavora su file nuovi (`NOME.min.img.xz` + `.sha256`), senza password; il risultato e' controllato con
  `e2fsck`. Accetta anche un `.img.xz`. Richiede e2fsprogs (`brew install e2fsprogs`); la sola compressione no.
- **Ripristina:** trascina un `.img` o `.img.xz` (o sceglilo dall'Archivio), scegli la scheda, conferma digitando il
  nome del disco. Scrive (decomprimendo al volo), rilegge la scheda e confronta lo SHA256, poi la espelle.
  Durante tutto il lavoro macOS non puo' montare la scheda (altrimenti scriverebbe sui volumi e la verifica fallirebbe).
- **Archivio:** i backup salvati in `~/Documents/SDClone`, con ripristino, Ottimizza, Finder e Cestino. **Comprimi** trasforma un
  `.img` gia' fatto in `.img.xz` senza password e lasciando l'originale.
- **Espelli:** pulsante ⏏ su ogni scheda e dopo un backup.
- Avanzamento con anello, velocita', tempo stimato e grafico; Annulla in qualsiasi momento. Percentuale sull'icona del
  Dock, notifica e suono a lavoro finito (Impostazioni ⌘,).
- Menu completi con scorciatoie (⌘1-⌘4 sezioni, ⌘O apri immagine, ⌘E espelli), **Guida** con ricerca (⌘?),
  **Informazioni su SD Clone**, **Avvertenze** in italiano e inglese (da accettare al primo avvio), Privacy e componenti
  di terze parti. Le immagini si aprono anche dal Finder («Apri con» / trascinandole sull'icona).
- La password di amministratore e' chiesta da macOS al momento di leggere/scrivere sulla scheda: l'app resta un normale
  processo utente. (Soluzione provvisoria: nella fase 4 diventa un helper privilegiato con `SMAppService`.)

### Provarla senza SD
```bash
SDCLONE_DEMO=1 "build/SD Clone.app/Contents/MacOS/SDClone"
# stati iniziali: SDCLONE_DEMO_STATE=backup|backup-run|restore|restore-run|confirm|library|compress-run|
#                                    optimize|optimize-run   (SDCLONE_DEMO_NO_E2FS=1: come senza e2fsprogs)
# velocita' simulata: SDCLONE_DEMO_SPEED=6    errore simulato: SDCLONE_DEMO_FAIL=1
# foto della finestra in un PNG: SDCLONE_SNAPSHOT=/tmp/foto.png SDCLONE_SNAPSHOT_DELAY=3
```

## Sicurezza
Una scheda e' selezionabile solo se il disco e' fisico, intero e non di sistema, e se e' removibile ed espellibile
(o bus SD) oppure ha una dimensione plausibile per una SD (<= 512 GB). Il disco interno del Mac e i dischi esterni di
grandi dimensioni sono sempre bloccati, sia nell'app sia nel comando. Vedi `Sources/SDCore/SafetyPolicy.swift`.
Prima di scrivere, l'app chiede di digitare il nome del disco e il comando lo ricontrolla.

## Da terminale
```bash
swift build -c release
.build/release/sdclone list            # SD selezionabili
.build/release/sdclone list --all      # tutti i dischi, con il motivo dei blocchi

# Backup: solo lettura. Copia fino alla fine dell'ultima partizione (--full per tutto il disco)
sudo .build/release/sdclone backup disk4                  # -> ~/Documents/SDClone/sdclone-<data>.img + .sha256
sudo .build/release/sdclone backup disk4 -o ~/Desktop/pi.img
sudo .build/release/sdclone backup disk4 --xz             # -> .img.xz, compresso al volo su piu' core

# Comprimi un backup gia' fatto (niente sudo; l'originale resta dov'e')
.build/release/sdclone compress ~/Documents/SDClone/pi.img   # -> pi.img.xz + pi.img.xz.sha256

# Ottimizza (niente sudo; l'originale resta com'e'): riduce al minimo e comprime -> pi.min.img.xz + .sha256
.build/release/sdclone optimize ~/Documents/SDClone/pi.img --clean   # --clean: toglie anche le cronologie
#   --keep-img conserva anche pi.min.img, --no-xz non comprime, --no-shrink non riduce, -o CARTELLA altrove

# Ripristino: SOVRASCRIVE la SD. Chiede di digitare il nome del disco, poi scrive, rilegge e confronta lo SHA256
sudo .build/release/sdclone restore ~/Documents/SDClone/pi.img disk4      # anche .img.xz

swift test
```
L'immagine ottenuta dal backup e' un normale file `.img`, utilizzabile anche con altri strumenti. Il `.img.xz` e' un
normale `.xz` (un solo stream a piu' blocchi, come `xz -T0`): lo leggono `xz`, 7-Zip e Raspberry Pi Imager.
Il file `.sha256` accanto contiene sempre lo SHA256 dell'immagine **non compressa**; per controllarlo:
`xz -dc pi.img.xz | shasum -a 256`.

I test usano solo file normali: nessuno scrive su un disco vero.

### Permessi di macOS
Anche con `sudo`, macOS blocca l'accesso diretto ai dischi (errore «Operation not permitted») se l'app da cui lanci il
comando non ha **Accesso completo al disco** (Impostazioni di Sistema › Privacy e sicurezza). Va concesso al Terminale
(o a Visual Studio Code, iTerm…) e, per l'app, a SD Clone; poi l'app va chiusa e riaperta.

## Procedure sulle immagini
Ridurre o espandere il filesystem di un `.img`, ed espandere la rootfs su una scheda già scritta:
**[docs/procedure-immagini.md](docs/procedure-immagini.md)** (strumento: `scripts/sdimg.sh`).

## Struttura
- `Sources/SDCore` – motore: elenco dischi, `SafetyPolicy`, `BackupEngine`, `RestoreEngine`, stato del lavoro.
- `Sources/sdclone` – comando da terminale; nell'app e' l'helper eseguito come amministratore.
- `Sources/SDCloneApp` – interfaccia SwiftUI.
- `scripts/` – `build-app.sh` (pacchetto .app), `make-icon.swift` (icona disegnata da codice), `sdimg.sh` (riduce/espande le immagini).
- `docs/` – procedure operative.

## Licenza

[MIT](LICENSE) © 2026 Maurizio Tolfa. Software fornito «così com'è», senza garanzie: vedi le Avvertenze nell'app
(menu Aiuto).

## Roadmap
1. [x] Elenco dischi e filtro di sicurezza
2. [x] Backup e ripristino da riga di comando (progresso, tempo stimato, SHA256, verifica)
3. [x] GUI SwiftUI (backup, ripristino, archivio) – da provare con una SD vera
4. [ ] Helper privilegiato (`SMAppService`), clone SD -> SD, golden image CGSLIM
   - [x] compressione `.xz` in parallelo (backup, «Comprimi», ripristino da `.xz`)
   - [x] riduzione tipo PiShrink su una **copia** (app › Ottimizza, `sdclone optimize`), golden provata su Raspberry;
         l'espansione si fa sul Pi con `raspi-config` (nessuna riespansione automatica)
   - [ ] e2fsprogs dentro l'app (oggi da Homebrew)
5. [ ] Firma Developer ID, notarizzazione, DMG, release su GitHub. Versione unica in `Sources/SDCore/Version.swift`.
   Il **Mac App Store non e' praticabile**: richiede la sandbox, che vieta scrittura diretta su `/dev/rdisk`, richiesta
   dei privilegi di amministratore e avvio di strumenti esterni (per lo stesso motivo Raspberry Pi Imager e Etcher sono
   distribuiti fuori dallo Store).
