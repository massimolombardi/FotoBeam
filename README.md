# FotoBeam

FotoBeam è una piccola app macOS nativa, scritta in SwiftUI, per caricare in batch cartelle di foto e video su Google Photos.

L'idea è semplice: scegli una cartella principale, FotoBeam trova le sottocartelle con file multimediali, le tratta come album, ti permette di controllare nomi e contenuti, poi crea gli album su Google Photos e carica i file selezionati.

## Funzionalità

- Scansione di una cartella principale con sottocartelle-album.
- Rilevamento di file `jpg`, `jpeg`, `png`, `heic`, `heif`, `webp`, `gif`, `mp4`, `mov` e `avi`.
- Nome album modificabile prima dell'upload.
- Revisione manuale dei file per album prima dell'upload.
- Segnalazione locale di duplicati esatti, foto molto simili e immagini potenzialmente sfocate.
- Confronto affiancato dei gruppi di foto duplicate o simili.
- Segnalazione di foto da valutare con motivi espliciti, come molto scura, sovraesposta, bassa risoluzione o gruppo simile numeroso.
- Dimensione miniature regolabile durante la revisione.
- Anteprima e rinomina esplicita dei file selezionati con formato data/ora dello scatto.
- Upload su Google Photos tramite OAuth.
- Report locale per riprendere un upload interrotto e saltare file già completati.
- Log e barra di avanzamento durante l'esecuzione.

## Requisiti

- macOS 14 o superiore.
- Swift 6 o superiore.
- Un progetto Google Cloud con OAuth configurato per app desktop.
- Accesso a Google Photos con il permesso `photoslibrary.appendonly`.

## Configurazione Google OAuth

1. Crea o apri un progetto in Google Cloud Console.
2. Abilita le API necessarie per Google Photos.
3. Configura la schermata di consenso OAuth.
4. Crea un client OAuth di tipo applicazione desktop.
5. Scarica il JSON delle credenziali.
6. Copia il file di esempio:

```bash
cp credentials.example.json credentials.json
```

7. Inserisci in `credentials.json` i valori del client OAuth scaricato da Google.

Il file `credentials.json` è locale e non deve essere committato.

## Avvio

Da root del progetto:

```bash
swift run FotoBeam
```

Al primo upload l'app apre il browser per completare l'autenticazione Google. Dopo il consenso, FotoBeam salva un token locale e lo riutilizza per le esecuzioni successive.

## Come Usarla

1. Avvia l'app.
2. Premi `Scegli cartella principale`.
3. Seleziona una cartella che contiene sottocartelle con foto o video.
4. Controlla gli album trovati.
5. Modifica i nomi degli album Google, se necessario.
6. Usa il pulsante `Revisiona` per confrontare i file dell'album.
7. Deseleziona gli album che non vuoi caricare.
8. Premi `Avvia upload selezionati`.

Ogni sottocartella con file compatibili diventa un album. Se un upload viene interrotto, il report locale permette all'app di riprendere evitando i file già marcati come completati.

## Revisione Prima Dell'Upload

FotoBeam analizza i file localmente e mostra eventuali avvisi nella schermata `Revisiona`:

- duplicati esatti, rilevati con hash del file;
- foto molto simili, rilevate con una firma visiva dell'immagine;
- immagini potenzialmente sfocate, rilevate con un punteggio euristico di nitidezza.
- foto da valutare, rilevate con segnali locali spiegabili come luminosità, contrasto, risoluzione, uniformità e numerosità dei gruppi simili.

Le viste `Duplicati` e `Simili` mostrano le foto a gruppi, affiancate orizzontalmente, così puoi confrontarle e scegliere quali caricare. La vista `Qualità bassa` raccoglie invece le immagini sfocate o sotto soglia. Lo slider con le icone foto permette di aumentare o ridurre la dimensione delle miniature.

La vista `Da valutare` non decide cosa è inutile: mostra solo immagini sospette con il motivo della segnalazione, lasciando sempre a te la scelta finale.

Gli avvisi non modificano mai automaticamente la selezione. Ogni file resta sotto il tuo controllo: puoi caricare tutto, non caricare nulla, oppure scegliere una foto alla volta usando le spunte nella griglia di revisione.

Le scelte sono non distruttive: FotoBeam non elimina, sposta o rinomina file locali. I file non selezionati vengono semplicemente esclusi da quell'upload.

## Rinomina File

Dalla schermata `Revisiona` puoi aprire `Anteprima rinomina` per vedere i nuovi nomi proposti per i soli file selezionati per l'upload.

Puoi anche attivare il flag `Rinomina prima dell'upload`: se abilitato, FotoBeam applica la rinomina ai file selezionati subito prima di caricarli. Se il flag è spento, i file vengono caricati con il nome corrente.

Il formato predefinito è corto, ordinabile e conserva tipo media, data e ora nel nome:

```text
IMG_yyyy-MM-dd_HH-mm-ss_001.ext
VID_yyyy-MM-dd_HH-mm-ss_001.ext
```

Esempio:

```text
IMG_2024-08-17_15-42-09_001.heic
VID_2024-08-17_15-42-09_001.mov
```

FotoBeam usa, in ordine, data EXIF dello scatto, metadata immagine, data già presente nel nome `IMG/VID_yyyy-MM-dd_HH-mm-ss_001`, data creazione file e data modifica file. Il nome originale non viene appeso al nuovo nome; viene salvato solo nello storico locale.

Se i metadata vengono persi, data e ora restano ricostruibili dal nome generato.

La rinomina non parte mai senza una scelta esplicita: puoi applicarla dalla preview con `Applica rinomina`, oppure abilitarla con il flag `Rinomina prima dell'upload`. Lo storico viene salvato in `rename_history.json`, escluso da git perché contiene percorsi locali e nomi file personali.

## File Locali

Questi file sono generati o usati localmente e sono esclusi da git:

- `credentials.json`: credenziali OAuth Google.
- `token_swift.json`: token OAuth salvato dopo l'autenticazione.
- `report_upload_swift.json`: stato degli upload, album, file già processati e percorsi locali.
- `rename_history.json`: storico delle rinomine applicate, con vecchi e nuovi percorsi locali.
- `.build/`: artefatti di build Swift Package Manager.

Nel repository sono presenti solo esempi sanificati:

- `credentials.example.json`
- `report_upload_swift.example.json`

Non committare credenziali, token, report reali, log o file contenenti percorsi personali.

## Privacy e Sicurezza

FotoBeam lavora con file locali e Google Photos. Per un repository pubblico è importante tenere fuori da git:

- token OAuth;
- client secret Google;
- report di upload reali;
- nomi di album personali, nomi di file e percorsi assoluti;
- log generati durante test o upload.

Il `.gitignore` del progetto è configurato per ignorare questi file. Prima di fare push puoi controllare cosa verrebbe pubblicato con:

```bash
git status --short
git ls-files --others --exclude-standard
```

## Risoluzione Problemi

Se l'app non trova `credentials.json`, verifica di averlo creato nella root del progetto.

Se l'autenticazione Google fallisce, elimina `token_swift.json` e riprova il login.

Se vuoi rifare un upload da zero, elimina o rinomina `report_upload_swift.json`.

Se alcuni file vengono saltati, apri la vista `File` dell'album e controlla il motivo indicato nella tabella.

## Struttura Del Progetto

```text
.
├── Package.swift
├── Sources/
│   └── FotoBeam/
│       ├── App/
│       │   ├── AppModel.swift
│       │   └── FotoBeamApp.swift
│       ├── Models/
│       │   └── Models.swift
│       ├── Services/
│       │   ├── AlbumScanner.swift
│       │   ├── GoogleAuth.swift
│       │   ├── GooglePhotosClient.swift
│       │   ├── QualityAnalyzer.swift
│       │   ├── RenamePlanner.swift
│       │   ├── ThumbnailLoader.swift
│       │   └── UploadReportStore.swift
│       ├── Support/
│       │   ├── AppConstants.swift
│       │   ├── AppError.swift
│       │   └── ProjectPaths.swift
│       └── Views/
│           ├── ContentView.swift
│           └── FileReviewView.swift
├── credentials.example.json
├── report_upload_swift.example.json
└── README.md
```

## Stato Del Progetto

FotoBeam è un tool personale e leggero, pensato per semplificare upload batch verso Google Photos da macOS. Non è un client Google Photos completo: si concentra su creazione album, caricamento file e ripresa degli upload interrotti.
