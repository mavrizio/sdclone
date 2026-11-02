# Pubblicare una versione di SD Clone

SD Clone si distribuisce **fuori dal Mac App Store**, come Raspberry Pi Imager ed Etcher. Lo Store impone la sandbox,
che vieta tre cose necessarie all'app: la scrittura diretta sulle schede (`/dev/rdisk`), la richiesta della password
di amministratore e l'avvio di strumenti esterni (e2fsprogs).

La versione da scaricare è:
- un **DMG** con l'app universale (Apple Silicon e Intel);
- firmato con il certificato **Developer ID**;
- **notarizzato** da Apple, così si apre senza avvisi di sicurezza;
- pubblicato nelle Release di GitHub.

## Preparazione (una volta sola)

### 1. Certificato «Developer ID Application»

Lo può creare solo il titolare dell'account (Account Holder).

1. Apri Xcode › Impostazioni › **Account** e aggiungi l'Apple ID, se non c'è.
2. Seleziona il team › **Gestisci certificati…** › **+** › **Developer ID Application**.
3. Controlla dal Terminale. Deve comparire una riga `Developer ID Application: Maurizio Tolfa (XXXXXXXXXX)`:

   ```bash
   security find-identity -v -p codesigning
   ```

In alternativa senza Xcode: developer.apple.com › Certificates › **+** › Developer ID Application, con una richiesta
di certificato creata da Accesso Portachiavi › Assistente Certificato.

### 2. Team ID

È il codice di 10 caratteri fra parentesi nel nome del certificato. Si trova anche su
[developer.apple.com/account](https://developer.apple.com/account) › **Membership details**.

### 3. Password per la notarizzazione

1. Su [account.apple.com](https://account.apple.com) › **Accesso e sicurezza** › **Password specifiche per le app**,
   creane una chiamata `sdclone-notary`.
2. Salvala nel portachiavi del Mac con questo comando. La password viene chiesta dal comando stesso e resta solo nel
   portachiavi, mai nei file del progetto:

   ```bash
   xcrun notarytool store-credentials sdclone-notary --apple-id TUA@EMAIL --team-id TEAMID
   ```

## Ogni nuova versione

1. Aumenta la versione in `Sources/SDCore/Version.swift`:
   - `marketing`, per esempio 1.0.1;
   - `build`, sempre +1.
2. Lancia i test e il rilascio:

   ```bash
   swift test
   scripts/release.sh
   ```

   Lo script:
   1. compila l'app universale in `build/release/`;
   2. la firma (hardened runtime e marca temporale);
   3. crea `SDClone-<versione>.dmg` con l'app, il collegamento ad Applicazioni e la licenza;
   4. lo invia ad Apple e attende la notarizzazione;
   5. ci attacca il biglietto (staple);
   6. scrive lo SHA256.
3. Prova il DMG su un Mac diverso, o su un altro utente: deve aprirsi con un doppio clic, senza avvisi di sicurezza.
4. Su GitHub › Releases › **Draft a new release**:
   - tag `v<versione>`;
   - allega il DMG e il suo `.sha256`;
   - scrivi le novità.

Per provare la procedura senza certificato (il DMG non è distribuibile):

```bash
SIGN_ID=- scripts/release.sh --no-notarize
```

## Da verificare alla prima versione firmata

- [ ] Backup e ripristino funzionano con la firma Developer ID e l'hardened runtime: la richiesta della password
      passa da AppleScript.
- [ ] Dopo l'installazione in Applicazioni va concesso di nuovo «Accesso completo al disco»: la firma è diversa da
      quella della build locale.
- [ ] La guida (Permessi di macOS) corrisponde a ciò che si vede davvero.
