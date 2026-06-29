# FotoBeam

FotoBeam è una piccola app macOS nativa, scritta in SwiftUI, per caricare in batch cartelle di foto e video su Google Photos.

L'idea è semplice: scegli una cartella principale, FotoBeam trova le sottocartelle con file multimediali, le tratta come album, ti permette di controllare nomi e contenuti, poi crea gli album su Google Photos e carica i file selezionati.

## Funzionalità

- Scansione di una cartella principale con sottocartelle-album.
- Rilevamento di file `jpg`, `jpeg`, `png`, `heic`, `heif`, `webp`, `gif`, `mp4`, `mov` e `avi`.
- Nome album modificabile prima dell'upload.
- Anteprima dei file che verranno caricati o saltati.
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
6. Usa il pulsante `File` per vedere cosa verrà caricato o saltato.
7. Deseleziona gli album che non vuoi caricare.
8. Premi `Avvia upload selezionati`.

Ogni sottocartella con file compatibili diventa un album. Se un upload viene interrotto, il report locale permette all'app di riprendere evitando i file già marcati come completati.

## File Locali

Questi file sono generati o usati localmente e sono esclusi da git:

- `credentials.json`: credenziali OAuth Google.
- `token_swift.json`: token OAuth salvato dopo l'autenticazione.
- `report_upload_swift.json`: stato degli upload, album, file già processati e percorsi locali.
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
│       └── main.swift
├── credentials.example.json
├── report_upload_swift.example.json
└── README.md
```

## Stato Del Progetto

FotoBeam è un tool personale e leggero, pensato per semplificare upload batch verso Google Photos da macOS. Non è un client Google Photos completo: si concentra su creazione album, caricamento file e ripresa degli upload interrotti.
