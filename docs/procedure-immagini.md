# Procedure sulle immagini: ridurre ed espandere il filesystem

Guida pratica per le immagini `.img` di Raspberry Pi (MBR: partizione 1 FAT32 di boot, partizione 2 ext4 `rootfs`
**ultima** del disco). Serve a te, da terminale, e a Claude quando gli chiedi di farlo.

Stato: gli script e i comandi segnati con ✅ sono stati **provati** su `slim_4_20_125_dev_shrink.img`
(Raspbian 12 bookworm, 1 nov 2026). Quelli segnati con ⚠️ sono comandi standard di Linux **non provati** su questa immagine.
Nessuna immagine ridotta è ancora stata provata su un Raspberry vero.

## In breve

| Voglio… | Dove | Comando |
|---|---|---|
| Vedere com'è fatta un'immagine e quanto si può ridurre | Mac | `scripts/sdimg.sh info IMG` ✅ |
| **Ridurre** un'immagine al minimo (e ripulirla, comprimerla) | Mac | app SD Clone › **Ottimizza**, oppure `.build/release/sdclone optimize IMG [--clean]` ✅ (o lo script: `scripts/sdimg.sh shrink IMG`) |
| **Espandere** un'immagine a una dimensione precisa | Mac | `scripts/sdimg.sh expand IMG 16GB` ✅ |
| **Espandere** la rootfs su una scheda già scritta | Raspberry | `sudo raspi-config nonint do_expand_rootfs && sudo reboot` ✅ (provato il 2 nov 2026 sulla golden: 5,8 → 28,3 GB su SD da 32 GB) |
| Scrivere un'immagine su una SD | Mac | app SD Clone › Ripristina, oppure `sudo .build/release/sdclone restore IMG diskN` ✅ |
| Comprimere un'immagine per Google Drive | Mac | app › Archivio › Comprimi, oppure `.build/release/sdclone compress IMG` ✅ |

Gli script non scrivono **mai** sull'immagine di partenza: creano un file nuovo e rifiutano di sovrascrivere.

## Prerequisiti (una volta sola)

```bash
brew install e2fsprogs        # fornisce e2fsck e resize2fs (installato "keg-only": lo script lo trova da solo)
```

Non serve `sudo` per lavorare sui file `.img`. Serve solo per leggere/scrivere una SD vera.

---

## Procedura 1 — Espandere la rootfs su una scheda già scritta (sul Raspberry) ✅/⚠️

Quando: hai scritto un'immagine ridotta (o più piccola della scheda) e vuoi usare tutto lo spazio della SD.
Le immagini ridotte con questa guida **non si espandono da sole** (vedi «Cose da non fare»): va fatto a mano, una volta.

1. Avvia il Raspberry con la scheda e apri un terminale (SSH o locale). Guarda la situazione:
   ```bash
   lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT      # la partizione 2 e' piu' piccola del disco?
   df -h /
   ```
2. Espandi (ricrea la partizione 2 con lo **stesso settore iniziale** fino a fine disco, poi al riavvio allarga il filesystem):
   ```bash
   sudo raspi-config nonint do_expand_rootfs
   sudo reboot
   ```
3. Dopo il riavvio controlla:
   ```bash
   lsblk -o NAME,SIZE,MOUNTPOINT
   df -h /                                   # ora Size deve essere vicina alla capacita' della SD
   ```

Cosa fa `do_expand_rootfs` ✅ (letto nel `raspi-config` dell'immagine): usa `parted` per verificare che la rootfs sia
l'**ultima** partizione, con `fdisk` la cancella e la ricrea dallo stesso settore iniziale, e installa lo script
`/etc/init.d/resize2fs_once`, che al riavvio successivo esegue `resize2fs` e poi si rimuove da solo. `parted`, `fdisk`,
`resize2fs` e `lsblk` sono presenti nell'immagine.

Se dopo il riavvio la dimensione non è cambiata ⚠️ (comandi standard, non provati qui):
```bash
lsblk                                         # la partizione 2 e' gia' grande? se si':
sudo resize2fs /dev/mmcblk0p2                 # allarga il filesystem a caldo fino a riempire la partizione
```
Se invece è la partizione a essere ancora piccola, ripeti il passo 2 e riavvia. Un `resize2fs` senza una partizione
più grande non fa niente.

---

## Procedura 2 — Espandere un'immagine sul Mac ✅

Quando: vuoi un `.img` già grande quanto la scheda di destinazione (o una dimensione scelta tu).

```bash
cd ~/Documents/GitHub/sdclone

# 1. quanto e' grande davvero la SD? (byte esatti: le "64 GB" commerciali non sono tutte uguali)
diskutil info -plist disk4 | plutil -extract TotalSize raw -o - -

# 2. espandi: DIMENSIONE puo' essere in byte oppure 16GB / 14.5GiB / 512MiB
scripts/sdimg.sh expand ~/Documents/SDClone/slim.min.img 15931539456 ~/Documents/SDClone/slim.15g.img
```

- Scegli una dimensione **minore o uguale** alla capacità reale della scheda (meglio qualche MiB in meno).
- Se ometti l'ultimo argomento il file si chiama `<immagine>.expanded.img`.
- Servono circa 2 volte la dimensione finale di spazio libero sul disco, per il lavoro intermedio.
- Il risultato viene controllato con `e2fsck` prima di dire «Fatto».

Controllo indipendente (sola lettura), che il filesystem occupi esattamente la partizione:
```bash
OFF=$((1056768*512))                          # inizio della partizione 2, da: scripts/sdimg.sh info IMG
$(brew --prefix e2fsprogs)/sbin/e2fsck -fn "IMG?offset=$OFF" | tail -1
```

## Procedura 3 — Ridurre un'immagine sul Mac ✅

```bash
scripts/sdimg.sh info   ~/Documents/SDClone/slim.img            # mostra la dimensione minima possibile
scripts/sdimg.sh shrink ~/Documents/SDClone/slim.img            # -> slim.min.img accanto all'originale
```

Esempio reale (`slim_4_20_125_dev_shrink.img`). Ripetuta due volte dà lo stesso risultato: cambiano solo 10 blocchi
(superblocco e copie di backup, che contengono delle date).

| | Originale | Ridotta |
|---|---|---|
| File | 14,84 GiB | 9,63 GiB |
| Compresso `.xz` | 3,72 GB | 2,89 GB |
| Durata | — | circa 20 secondi (misurato, SSD interno) |

Poi, se serve per Google Drive: `.build/release/sdclone compress slim.min.img` oppure Archivio › Comprimi nell'app.

**Dal 2 nov 2026 lo stesso procedimento è nell'app (› Ottimizza) e in `sdclone optimize`**, con in più la pulizia
delle cronologie, la compressione nello stesso passaggio e l'ingresso anche da `.img.xz`. Stesse regole: partizione
estratta in un file a parte, `resize2fs` mai con `?offset=`, MBR aggiornato, `e2fsck -fn` sul risultato, nessun file
sovrascritto.

---

## Cose da non fare (trappole trovate provando)

1. **Mai `resize2fs file.img?offset=N`** per ridurre o allargare. Con l'offset `resize2fs` tronca o estende il **file**
   usando solo la dimensione del filesystem, senza contare l'offset: la coda dell'immagine (qui 516 MiB) viene tagliata, e
   se stai allargando il filesystem risulta più grande della partizione (`e2fsck` non se ne accorge). Lo script estrae la
   partizione in un file a parte, la ridimensiona lì e la ricompone.
   Con `?offset=` vanno bene solo comandi in **sola lettura**: `e2fsck -fn`, `debugfs -R "…"`, `resize2fs -P`.
2. **Non aggiungere `init=/usr/lib/raspberrypi-sys-mods/firstboot` a `cmdline.txt`** sperando di avere l'espansione
   automatica: in questa immagine `firstboot` rigenera le chiavi SSH e cambia il PARTUUID, ma **non espande** niente. E
   `init_resize.sh` è la versione vecchia (cerca `/boot`, mentre il `fstab` ha `/boot/firmware`): potrebbe fallire.
3. **Non lavorare sull'unico esemplare di un'immagine.** Gli script producono file nuovi; se fai a mano, usa prima
   `cp -c originale copia` (clone APFS istantaneo, non occupa spazio finché non cambia).
4. **Non modificare `cmdline.txt` o altri file della FAT con script fatti di fretta**: con un mio primo tentativo la
   voce di directory non è stata aggiornata e la modifica è risultata a metà. Se serve, ⚠️ (non provato) montare solo la FAT
   in lettura/scrittura con `hdiutil attach -nomount` + `diskutil mount`, ed eliminare le tracce di macOS
   (`.fseventsd`, `.Spotlight-V100`, `.Trashes`); poi confrontare i byte prima e dopo.
5. **`dumpe2fs` non accetta `?offset=`**: per leggere lo stato dei blocchi usa `debugfs -R "testb N COUNT"`.

## Come verificare un'immagine prima di fidarsene

Dalla più economica alla più completa (✅ tutte usate sull'immagine ridotta):

1. `e2fsck -fn "IMG?offset=OFF"` → «clean», stesso numero di file dell'originale.
2. Hash: `shasum -a 256 IMG` uguale al `.sha256` registrato; per un `.xz`: `xz -dc IMG.xz | shasum -a 256`.
3. Che l'inizio della partizione di boot sia identico: confronto byte per byte della zona 0 … `START*512` con
   l'originale (devono differire solo i 4 byte dei «settori» della partizione 2 nell'MBR).
4. Confronto dell'albero dei file originale ↔ ridotta, montando entrambe in sola lettura (serve il driver ext4, qui
   Paragon ExtFS):
   ```bash
   hdiutil attach -readonly -nobrowse -imagekey diskimage-class=CRawDiskImage -mountrandom /tmp/mA IMG_A
   hdiutil attach -readonly -nobrowse -imagekey diskimage-class=CRawDiskImage -mountrandom /tmp/mB IMG_B
   diff -rq /tmp/mA/dmg.xxxx /tmp/mB/dmg.yyyy      # 0 "differ" e 0 "Only in"; i "No such file" sono link assoluti
   hdiutil detach /dev/diskN                        # smonta entrambi
   ```
   `diff` non segue i link simbolici assoluti né legge file con accenti nel nome: confronta anche tipo, permessi,
   proprietario, data e destinazione dei link con uno script, e quel solo file con `debugfs -R "cat …"`.
5. **L'avvio su un Raspberry vero**, con una scheda di prova. È l'unica verifica che dimostra che l'immagine funziona.

---

## Istruzioni per Claude

Quando l'utente chiede di ridurre, espandere o "fare una procedura" su un'immagine:

1. Usa **`scripts/sdimg.sh`**. Non reinventare i comandi e non usare mai `resize2fs` su `file?offset=` (vedi sopra).
2. Prima `info`, poi l'azione. Scrivi il risultato in una cartella di lavoro o con un nome nuovo; **non** sovrascrivere né
   spostare file in `~/Documents/SDClone` senza averlo chiesto, e non toccare l'originale.
3. Verifica sempre almeno i punti 1-3 di «Come verificare»; per un'immagine destinata a una flotta anche il 4.
4. Non aggiungere meccanismi di auto-espansione (vedi «Cose da non fare», punto 2): spiega che serve la Procedura 1.
5. Di' chiaramente cosa è provato e cosa no, e che l'immagine va provata su un Raspberry prima di usarla.
6. Se il Pi non parte o `e2fsck` non è pulito: non correggere "a occhio"; fermati, mostra l'output e chiedi.
7. Se la richiesta è diversa (es. tabella GPT, ultima partizione non Linux, filesystem non ext4), lo script si ferma con
   un errore: spiega il motivo invece di forzare.

Stato a oggi: la funzione «Riduci…» dentro l'app **non esiste ancora**; entrerà solo se l'utente conferma che l'immagine
ridotta si avvia sul Raspberry. Fino ad allora lo script è lo strumento ufficiale.
