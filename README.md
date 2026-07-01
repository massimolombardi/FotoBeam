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

## Configurazione Google

FotoBeam usa la Google Photos Library API tramite OAuth 2.0. Non usa service account: Google Photos richiede l'accesso di un utente Google autenticato.

Documentazione ufficiale utile:

- [Configure your app](https://developers.google.com/photos/overview/configure-your-app)
- [Authorization scopes](https://developers.google.com/photos/overview/authorization)
- [Limits and quotas](https://developers.google.com/photos/overview/api-limits-quotas)

### Abilitare l'account Google

1. Vai su [Google Cloud Console](https://console.cloud.google.com/).
2. Crea un nuovo progetto, oppure selezionane uno esistente.
3. Apri `APIs & Services` > `Library`.
4. Cerca `Photos`.
5. Abilita la Google Photos Library API, o la voce Google Photos API equivalente mostrata nella console.
6. Apri `APIs & Services` > `OAuth consent screen`.
7. Configura la schermata di consenso:
   - per uso personale puoi lasciare l'app in modalità test;
   - aggiungi il tuo account Google tra i test users se la console lo richiede;
   - compila nome app, email supporto e dati sviluppatore richiesti.
8. Apri `APIs & Services` > `Credentials`.
9. Crea una credenziale OAuth:
   - `Create Credentials`;
   - `OAuth client ID`;
   - application type: `Desktop app`.
10. Scarica il JSON della credenziale OAuth.
11. Copia il file di esempio:

```bash
cp credentials.example.json credentials.json
```

12. Inserisci in `credentials.json` i valori del client OAuth scaricato da Google.

Il file `credentials.json` è locale e non deve essere committato.

### Scope OAuth Usato

FotoBeam richiede questo scope:

```text
https://www.googleapis.com/auth/photoslibrary.appendonly
```

Questo scope dà accesso in scrittura per caricare byte, creare media item, creare album e aggiungere contenuti. È intenzionalmente più ristretto degli scope completi: l'app deve solo creare nuovi album e caricare nuovi media, non leggere tutta la libreria Google Photos.

Nota: dal 2025 Google ha modificato/rimosso alcuni scope storici della Library API. Per FotoBeam non usare scope ampi come `photoslibrary` se non strettamente necessario.

### Primo Login

Al primo upload FotoBeam apre il browser e mostra la schermata di consenso Google. Dopo il consenso, il token locale viene salvato in `token_swift.json`.

Se l'app è ancora in test o non verificata, Google può mostrare un avviso `Unverified app`. Per uso personale puoi procedere con il tuo account di test. Per distribuire pubblicamente l'app serve la verifica OAuth di Google.

## Avvio

Da root del progetto:

```bash
swift run FotoBeam
```

Al primo upload l'app apre il browser per completare l'autenticazione Google. Dopo il consenso, FotoBeam salva un token locale e lo riutilizza per le esecuzioni successive.

Se la finestra dell'app non riceve la tastiera quando viene avviata da terminale, porta FotoBeam in primo piano con `Cmd+Tab` o clicca la finestra. Il progetto include codice AppKit per trasformare il processo SwiftPM in app foreground, ma macOS può essere severo con eseguibili lanciati da terminale.

## Come Usarla

1. Avvia l'app.
2. Premi `Scegli cartella principale`.
3. Seleziona una cartella che contiene sottocartelle con foto o video.
4. Controlla gli album trovati.
5. Modifica i nomi degli album Google, se necessario.
6. Usa il pulsante `Revisiona` per confrontare i file dell'album.
7. Scegli quali file caricare e quali saltare.
8. Se vuoi, abilita `Rinomina prima dell'upload`.
9. Deseleziona gli album che non vuoi caricare.
10. Premi `Avvia upload selezionati`.

Ogni sottocartella con file compatibili diventa un album. Se un upload viene interrotto, il report locale permette all'app di riprendere evitando i file già marcati come completati.

## Revisione Prima Dell'Upload

FotoBeam analizza i file localmente e mostra eventuali avvisi nella schermata `Revisiona`:

- duplicati esatti, rilevati con hash del file;
- foto molto simili, rilevate con una firma visiva dell'immagine;
- immagini potenzialmente sfocate, rilevate con un punteggio euristico di nitidezza;
- foto da valutare, rilevate con segnali locali spiegabili come luminosità, contrasto, risoluzione, uniformità e numerosità dei gruppi simili.

Le viste `Duplicati` e `Simili` mostrano le foto a gruppi, affiancate orizzontalmente, così puoi confrontarle e scegliere quali caricare. La vista `Qualità bassa` raccoglie invece le immagini sfocate o sotto soglia. Lo slider con le icone foto permette di aumentare o ridurre la dimensione delle miniature.

La vista `Da valutare` non decide cosa è inutile: mostra solo immagini sospette con il motivo della segnalazione, lasciando sempre a te la scelta finale.

Gli avvisi non modificano mai automaticamente la selezione. Ogni file resta sotto il tuo controllo: puoi caricare tutto, non caricare nulla, oppure scegliere una foto alla volta usando le spunte nella griglia di revisione.

Le scelte sono non distruttive: FotoBeam non elimina, sposta o rinomina file locali. I file non selezionati vengono semplicemente esclusi da quell'upload.

Eccezione esplicita: la funzione di rinomina modifica davvero i nomi dei file locali solo quando premi `Applica rinomina` oppure quando abiliti il flag `Rinomina prima dell'upload`.

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
- `.fotobeam-memory.md`: memoria locale di lavoro per continuare lo sviluppo senza perdere contesto.
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

Se Google mostra `access_denied` o l'account non può autorizzare l'app, verifica che:

- la Google Photos Library API sia abilitata nel progetto corretto;
- l'OAuth consent screen sia configurato;
- il tuo account sia tra i test users, se l'app è in modalità test;
- il client OAuth sia di tipo `Desktop app`;
- `credentials.json` contenga `client_id`, `client_secret`, `auth_uri` e `token_uri` corretti.

Se vuoi rifare un upload da zero, elimina o rinomina `report_upload_swift.json`.

Se alcuni file vengono saltati, apri la vista `Revisiona` dell'album e controlla stato, motivi qualità e spunte manuali.

Se vuoi rifare l'autorizzazione Google da zero, elimina `token_swift.json`.

Se hai applicato una rinomina e vuoi ricostruire cosa è successo, controlla `rename_history.json`.

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

## Note Di Sviluppo

Comandi principali:

```bash
swift build
swift run FotoBeam
```

Prima di pubblicare:

```bash
git status --short --ignored
git ls-files --others --exclude-standard
```

I file ignorati possono contenere credenziali, token OAuth, report con percorsi locali, storico rinomine e dati personali. Non forzarne il commit.
