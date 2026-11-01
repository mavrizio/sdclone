# sdclone

App per macOS per clonare, salvare e ripristinare schede SD (pensata per Raspberry Pi).

> Stato: **fase 1** – motore (`SDCore`) con elenco dei dischi e filtro di sicurezza. Backup, ripristino e GUI sono in arrivo.

## Sicurezza
Una scheda e' selezionabile solo se il disco e' fisico, esterno, intero e non di sistema, e se e' un supporto
removibile / bus SD oppure ha una dimensione plausibile per una SD (<= 512 GB). Il disco interno del Mac e i
dischi esterni di grandi dimensioni sono sempre bloccati. Vedi `Sources/SDCore/SafetyPolicy.swift`.

## Uso (provvisorio)
```bash
swift run sdclone list          # SD selezionabili
swift run sdclone list --all    # tutti i dischi, con il motivo dei blocchi
swift test
```

## Roadmap
1. [x] Elenco dischi e filtro di sicurezza
2. [ ] Backup e ripristino da riga di comando (progresso, tempo stimato, SHA256, verifica)
3. [ ] GUI SwiftUI
4. [ ] Helper privilegiato, compressione, clone SD -> SD, golden image CGSLIM
5. [ ] Firma, notarizzazione, DMG, release
