import Foundation

/// Avvertenze, privacy e componenti di terze parti, in italiano e in inglese.
/// Se il testo delle avvertenze cambia in modo sostanziale, aumentare `disclaimerRevision`: verra' richiesto di nuovo
/// di accettarlo all'avvio.
enum Legal {
    static let disclaimerRevision = 1

    enum Language: String, CaseIterable, Identifiable {
        case italian = "it", english = "en"
        var id: String { rawValue }
        var label: String { self == .italian ? "Italiano" : "English" }

        /// L'app e' in italiano: si parte in italiano, l'inglese si sceglie con il selettore.
        static var preferred: Language { .italian }
    }

    struct Section: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    // MARK: - Avvertenze

    static func disclaimerTitle(_ l: Language) -> String {
        l == .italian ? "Avvertenze e limitazione di responsabilità" : "Disclaimer and limitation of liability"
    }

    static func disclaimerIntro(_ l: Language) -> String {
        l == .italian
            ? "Prima di usare SD Clone leggi con attenzione queste condizioni. Usando il programma dichiari di averle lette e di accettarle."
            : "Please read these terms carefully before using SD Clone. By using the software you confirm that you have read and accepted them."
    }

    static func disclaimer(_ l: Language) -> [Section] {
        switch l {
        case .italian:
            return [
                Section(title: "1. Cosa fa il programma",
                        body: "SD Clone legge e scrive direttamente le schede di memoria. Il ripristino CANCELLA in modo definitivo e irreversibile tutto il contenuto della scheda scelta: i dati sovrascritti non si possono recuperare."),
                Section(title: "2. Fornito «così com'è»",
                        body: "SD Clone è software gratuito, fornito «così com'è» e «come disponibile», senza garanzie di alcun tipo, esplicite o implicite, comprese, a titolo di esempio, le garanzie di commerciabilità, di idoneità a uno scopo particolare, di assenza di errori e di non violazione di diritti di terzi. Non è garantito che il programma funzioni senza interruzioni o errori, né che i risultati siano corretti o adatti alle tue esigenze."),
                Section(title: "3. Limitazione di responsabilità",
                        body: "Nei limiti massimi consentiti dalla legge applicabile, l'autore e i collaboratori non sono responsabili di alcun danno, diretto o indiretto, incidentale, speciale, consequenziale o punitivo, compresi a titolo di esempio: perdita, corruzione o divulgazione di dati; danni a schede, computer, dispositivi o impianti; fermo di macchine o servizi; mancati guadagni; costi di ripristino. Questo vale per qualsiasi causa derivante dall'uso o dall'impossibilità di usare il programma, anche se l'autore è stato informato della possibilità di tali danni."),
                Section(title: "4. Responsabilità di chi lo usa",
                        body: "Sei tu a scegliere la scheda su cui scrivere e a confermare l'operazione: controlla sempre il nome e la capacità del disco. Conserva copie separate dei dati importanti. Verifica ogni immagine su un dispositivo di prova prima di usarla in produzione o di distribuirla. Chi crea o distribuisce un'immagine è responsabile del suo contenuto, comprese password, chiavi, credenziali, dati personali e licenze del software che contiene."),
                Section(title: "5. Protezioni",
                        body: "I controlli di sicurezza (esclusione dei dischi interni, conferma con il nome del disco, verifica SHA256, blocco del montaggio durante la scrittura) riducono i rischi ma non li eliminano. Schede difettose, contraffatte o lettori guasti possono produrre risultati errati anche quando il programma non segnala problemi."),
                Section(title: "6. Componenti di terze parti",
                        body: "Le funzioni Riduci e Togli le cronologie usano e2fsprogs (resize2fs, e2fsck, debugfs), software di terzi distribuito con licenza propria e installato separatamente. L'autore di SD Clone non risponde del suo funzionamento."),
                Section(title: "7. Marchi",
                        body: "SD Clone è un progetto indipendente, non affiliato, sponsorizzato o approvato da Raspberry Pi Ltd, Apple Inc. o SD Association. Raspberry Pi è un marchio di Raspberry Pi Ltd. Mac e macOS sono marchi di Apple Inc., registrati negli USA e in altri paesi. SD è un marchio di SD-3C LLC. Gli altri marchi appartengono ai rispettivi titolari."),
                Section(title: "8. Validità",
                        body: "Alcuni ordinamenti non consentono l'esclusione di determinate garanzie o la limitazione di alcune responsabilità: in tal caso le esclusioni e limitazioni qui sopra si applicano nella misura massima consentita. Restano salvi i diritti inderogabili riconosciuti dalla legge, per esempio in caso di dolo o colpa grave."),
            ]
        case .english:
            return [
                Section(title: "1. What the software does",
                        body: "SD Clone reads and writes memory cards directly. Restoring an image ERASES the entire content of the selected card permanently and irreversibly: overwritten data cannot be recovered."),
                Section(title: "2. Provided “as is”",
                        body: "SD Clone is free software provided “as is” and “as available”, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, freedom from errors and non-infringement. There is no guarantee that the software will run uninterrupted or error-free, or that its results will be correct or suitable for your needs."),
                Section(title: "3. Limitation of liability",
                        body: "To the maximum extent permitted by applicable law, the author and contributors shall not be liable for any direct, indirect, incidental, special, consequential or punitive damages, including but not limited to: loss, corruption or disclosure of data; damage to cards, computers, devices or equipment; downtime of machines or services; loss of profits; recovery costs. This applies to any cause arising out of the use of, or inability to use, the software, even if the author has been advised of the possibility of such damages."),
                Section(title: "4. Your responsibility",
                        body: "You choose the card to write to and you confirm the operation: always check the name and capacity of the disk. Keep separate copies of important data. Test every image on a spare device before using it in production or distributing it. Whoever creates or distributes an image is responsible for its content, including passwords, keys, credentials, personal data and the licences of the software it contains."),
                Section(title: "5. Safeguards",
                        body: "The safety checks (internal disks excluded, confirmation by typing the disk name, SHA-256 verification, automatic mounting blocked while writing) reduce risks but do not eliminate them. Faulty or counterfeit cards and defective readers may produce wrong results even when the software reports no problem."),
                Section(title: "6. Third-party components",
                        body: "The Shrink and Remove histories features use e2fsprogs (resize2fs, e2fsck, debugfs), third-party software distributed under its own licence and installed separately. The author of SD Clone is not responsible for its behaviour."),
                Section(title: "7. Trademarks",
                        body: "SD Clone is an independent project, not affiliated with, sponsored or endorsed by Raspberry Pi Ltd, Apple Inc. or the SD Association. Raspberry Pi is a trademark of Raspberry Pi Ltd. Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries. SD is a trademark of SD-3C LLC. Other trademarks belong to their respective owners."),
                Section(title: "8. Severability",
                        body: "Some jurisdictions do not allow the exclusion of certain warranties or the limitation of certain liabilities: in that case the exclusions and limitations above apply to the maximum extent permitted. Mandatory statutory rights, for example in cases of wilful misconduct or gross negligence, remain unaffected."),
            ]
        }
    }

    // MARK: - Privacy

    static func privacyTitle(_ l: Language) -> String { l == .italian ? "Privacy" : "Privacy" }

    static func privacy(_ l: Language) -> String {
        l == .italian
            ? "SD Clone non raccoglie, non invia e non condivide alcun dato. Non contiene statistiche d'uso, pubblicità né sistemi di tracciamento e non si collega a internet: tutto avviene sul tuo Mac. Le uniche connessioni sono i collegamenti che apri tu (per esempio la pagina del progetto). Le immagini e i file .sha256 restano nelle cartelle che scegli; le preferenze sono salvate solo sul Mac."
            : "SD Clone does not collect, send or share any data. It contains no analytics, advertising or tracking and does not connect to the internet: everything happens on your Mac. The only connections are links you open yourself (for example the project page). Images and .sha256 files stay in the folders you choose; preferences are stored only on your Mac."
    }

    // MARK: - Licenza

    static func licenseIntro(_ l: Language) -> String {
        l == .italian
            ? "SD Clone è software libero, distribuito con licenza MIT: puoi usarlo, copiarlo, modificarlo e ridistribuirlo, anche per scopi commerciali, purché venga mantenuto l'avviso di copyright qui sotto. Il testo che fa fede è quello originale in inglese."
            : "SD Clone is free software released under the MIT licence: you may use, copy, modify and redistribute it, including for commercial purposes, as long as the copyright notice below is retained."
    }

    static let mitLicense = """
    MIT License

    Copyright (c) 2026 Maurizio Tolfa

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    // MARK: - Terze parti

    static func thirdParty(_ l: Language) -> [Section] {
        [
            Section(title: "e2fsprogs",
                    body: l == .italian
                        ? "resize2fs, e2fsck e debugfs, di Theodore Ts'o e collaboratori. Licenza GNU GPL v2. Non sono inclusi in SD Clone: vengono usati se installati sul Mac (per esempio con Homebrew) e avviati come programmi separati."
                        : "resize2fs, e2fsck and debugfs, by Theodore Ts'o and contributors. GNU GPL v2 licence. They are not included in SD Clone: they are used if installed on the Mac (for example with Homebrew) and run as separate programs."),
            Section(title: "Formato .xz",
                    body: l == .italian
                        ? "La compressione e la decompressione .xz usano il framework Compression di Apple, incluso in macOS. Nessuna libreria esterna."
                        : "XZ compression and decompression use Apple's Compression framework, part of macOS. No external library."),
        ]
    }
}
