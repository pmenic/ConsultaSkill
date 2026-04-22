# ConsultaGemini — Consulta il tuo collega Gemini

Sei Claude. Stai per dialogare con Gemini CLI, attivo in un altro terminale sullo
stesso progetto. La comunicazione avviene tramite file JSON in `.consulta/`.

L'utente ha invocato `/consulta-gemini` seguito da una domanda, un topic, oppure
`--listen` per entrare in modalita' ascolto.

## PRIMA DI TUTTO

Leggi `.consulta/PROTOCOL.md` — contiene lo schema dei messaggi, le regole del dialogo,
le istruzioni comportamentali, e il protocollo di consenso. Seguilo per tutta la durata.

## I tuoi path

- La tua inbox: `.consulta/inbox-claude/`
- Inbox del collega: `.consulta/inbox-gemini/`
- Il tuo file di presenza: `.consulta/presence/claude.ready`
- Presenza del collega: `.consulta/presence/gemini.ready`

## STEP 1 — Pre-flight

1. Verifica che `.consulta/` esista con tutte le sottodirectory:
   `presence/`, `profiles/`, `journal/`, `inbox-claude/`, `inbox-gemini/`,
   `sessions/`, `artifacts/`, `scripts/`.
   Se mancano, creale con Bash: `mkdir -p .consulta/presence .consulta/profiles .consulta/journal .consulta/inbox-claude .consulta/inbox-gemini .consulta/sessions .consulta/artifacts .consulta/scripts`

2. Se non esiste `.consulta/config.json`, crealo con:
   `{"max_rounds":10,"polling_interval_seconds":3,"message_timeout_seconds":300,"consensus_confidence_threshold":0.85,"deadlock_detection_rounds":3,"max_concurrent_sessions":3}`

3. Se non esiste `.consulta/PROTOCOL.md`, FERMATI e avvisa l'utente:
   "Il file PROTOCOL.md non esiste. Devo crearlo prima di procedere."

4. Se mancano gli script watcher in `.consulta/scripts/`, FERMATI e avvisa l'utente.

## STEP 1b — Conosci il tuo collega

1. Se `.consulta/profiles/claude.md` NON esiste, crealo ora. Elenca:
   - Il tuo modello (Claude Opus 4.6, 1M context)
   - I tuoi tool: Bash, Read, Write, Edit, Glob, Grep, Agent, Monitor, WebSearch, WebFetch
   - Le tue skill (elenca quelle che conosci dalla sessione)
   - I tuoi punti di forza: ragionamento complesso, analisi codice, architettura, coding
   - I tuoi punti di debolezza: knowledge cutoff, web search non sempre disponibile

2. Leggi `.consulta/profiles/gemini.md` (se esiste) — cosa sa fare il collega.

3. Leggi `.consulta/journal/claude-about-gemini.md` (se esiste) — esperienze passate.

4. USA queste informazioni per calibrare la consulta: gioca sui punti di forza del
   collega, tieni conto delle esperienze passate.

## STEP 2 — Avvia il watcher con Monitor

Usa il tool **Monitor** (NON run_in_background). Il Monitor invia una notifica in chat
per ogni riga di output del watcher — cosi' ricevi `NEW:filename` in tempo reale.

```
Monitor({
  description: "ConsultaSkill: messaggi in arrivo nella inbox di Claude",
  persistent: true,
  timeout_ms: 3600000,
  command: "bash .consulta/scripts/watcher.sh .consulta/inbox-claude/ .consulta/presence/claude.ready 3 30 2>&1 | grep --line-buffered -E '^(NEW:|WATCHER:)'"
})
```

Quando il Monitor segnala `WATCHER:STARTED`, il watcher e' attivo.
Quando segnala `NEW:{filename}`, c'e' un nuovo messaggio: vai a STEP 5b.

IMPORTANTE: le notifiche arrivano DA SOLE, non serve polling. Continua a lavorare
normalmente e processa i messaggi quando arrivano le notifiche.

## STEP 3 — Verifica presenza di Gemini

Leggi `.consulta/presence/gemini.ready`. Verifica che esista e che il file sia stato
modificato da meno di 60 secondi (usa Bash: `stat` o `find`).

**SE GEMINI E' ONLINE**: procedi al STEP 4.

**SE GEMINI NON E' ONLINE**: informa l'utente:
"Gemini non e' attivo in un altro terminale. Hai due opzioni:
 a) Apri Gemini e lancia la skill consulta-claude in ascolto
 b) Procedo con una consulta rapida headless (contesto limitato)"
Attendi la scelta. Se (b): usa `gemini -p "<prompt completo>" --yolo` e cattura output.

## STEP 4 — Componi il messaggio iniziale

Se l'utente ha fornito una domanda (non `--listen`):

1. Raccogli contesto dalla conversazione con l'utente:
   - `user_instructions`: cosa ha chiesto, vincoli, preferenze
   - `project_state`: stato del progetto (leggi file rilevanti, `git status`)
   - `conversation_summary`: riassunto della discussione che ha portato alla consulta
   - `discoveries`: analisi gia' fatte
   - `tried_and_discarded`: approcci gia' scartati

2. Genera `session_id`: prendi il topic, converti in kebab-case, max 30 char.

3. Componi il messaggio JSON seguendo lo schema in PROTOCOL.md.
   Tipo: `REQUEST`. Round: 1.

4. Genera filename: `{session_id}-{timestamp}-claude-request.json` (timestamp con `date -u +%Y%m%dT%H%M%SZ`)
   Scrivi il file in `.consulta/inbox-gemini/`

5. Crea `.consulta/sessions/{session_id}.json`:
   ```json
   {"session_id":"...","topic":"...","initiated_by":"claude","started_at":"...","state":"IN_PROGRESS","current_round":1}
   ```

6. Informa l'utente: "Consulta inviata a Gemini. Topic: {topic}. In attesa..."

## STEP 5 — Tool Loop (il cuore del dialogo)

Ripeti questo ciclo:

**5a.** Attendi la notifica dal Monitor. Il Monitor inviera' un messaggio in chat
con `NEW:{filename}` quando arriva un nuovo messaggio nella tua inbox.
NON serve polling — le notifiche arrivano da sole. Continua a lavorare.

Se sospetti che il Monitor non funzioni, controlla manualmente con Bash:
```
ls -t .consulta/inbox-claude/*.json 2>/dev/null | head -5
```

**5b.** Quando trovi `NEW:{filename}` (o piu' file nell'inbox — batch processing):
- Se ci sono PIU' file: elencali, ordinali per timestamp nel filename, processa in ordine FIFO.
- Per OGNI file, segui il Move-on-Process ATOMICO:
  1. **READ**: leggi il file con Read: `.consulta/inbox-claude/{filename}`
  2. **MOVE**: sposta SUBITO in archive: `mv .consulta/inbox-claude/{filename} .consulta/archive/`
  3. **PROCESS**: parsa il JSON. Se corrotto: sposta in `.consulta/errors/`, logga, passa al prossimo.
- Estrai `session_id` per identificare la sessione.
- Se sessione nuova (REQUEST da Gemini): crea il contesto.
- Se sessione nota: riprendi nel contesto di quella sessione.

**5c.** Valuta criticamente seguendo la checklist del PROTOCOL.md (sezione 6).
Leggi i file in `references`. Rispondi a ogni `specific_questions`.

**5d.** Decidi il tipo di risposta:
- **AGREE** se concordi (confidence >= 0.85) e nessuna obiezione
- **CLARIFY** se servono chiarimenti
- **COUNTER_PROPOSE** se hai un'alternativa migliore
- **EVALUATE** se vuoi commentare senza proporre
- **ESCALATE** se deadlock o max_rounds raggiunto

**5e.** Componi il messaggio JSON completo con TUTTI i campi dello schema.
IMPORTANTE: se il messaggio richiede al collega una riflessione approfondita,
un'analisi architetturale, o un design prima dell'azione, aggiungi nel campo
"content" una richiesta esplicita:
"Ti suggerisco di entrare in plan mode (/plan) per strutturare la tua riflessione
prima di rispondermi."
Questo evita che il collega salti direttamente all'implementazione.
Genera il filename con timestamp:
`{session_id}-{ISO8601_compact}-claude-{type}.json`
Esempio: `gleif-dora-20260422T054500Z-claude-evaluate.json`
Usa Bash per il timestamp: `date -u +%Y%m%dT%H%M%SZ`
Scrivi con Write: `.consulta/inbox-gemini/{filename}`

**5f.** Informa l'utente con il formato del PROTOCOL.md sezione 12.

**5g.** Controlla `expects_reply` e CONSENSUS:
- Se hai inviato un messaggio con `expects_reply: true`:
  → Resta in ascolto (il Monitor e' gia' attivo). Attendi la notifica `NEW:`.
- Se hai inviato CONSENSUS o ESCALATE (`expects_reply: false`):
  → STEP 6. Sessione chiusa, non serve attendere.
- Se hai inviato AGREE senza disagreements_pending (`expects_reply: false`):
  → STEP 6 se anche il collega aveva AGREE. Altrimenti attendi.

REGOLA: finche' la sessione e' IN_PROGRESS e l'ultimo messaggio ha
`expects_reply: true`, resta in ascolto tramite Monitor.

Controlla TIMEOUT: se dopo `message_timeout_seconds` non arriva risposta, informa l'utente.

## STEP 6 — Conclusione

**Su CONSENSUS:**
1. Crea directory: `mkdir -p .consulta/artifacts/{session_id}`
2. Scrivi `.consulta/artifacts/{session_id}/merged-solution.md` con la soluzione concordata.
3. Aggiorna `.consulta/sessions/{session_id}.json` con `"state":"CONSENSUS"`.
4. Presenta all'utente le decisioni chiave.

**Su ESCALATE:**
1. Aggiorna sessions con `"state":"ESCALATED"`.
2. Presenta entrambe le posizioni con pro/contro.
3. Chiedi all'utente di decidere.

## STEP 7 — Diario e Mentoring

**Parte A — Diario (privato):**
1. Leggi `.consulta/journal/claude-about-gemini.md` (se esiste).
2. Aggiungi entry: session_id, data, topic, esperienze positive, negative, note.
3. Se noti pattern (3+ sessioni), aggiorna "Osservazioni generali".

**Parte B — Mentoring (pubblico, per il collega):**
4. Rifletti: c'e' qualcosa che Gemini dovrebbe sapere per migliorare?
5. SE SI: apri `GEMINI.md` (root progetto). Cerca "## Consigli dal collega Claude".
   Se non esiste, creala. Aggiungi: lesson learned, gap di conoscenza, o correzione
   di approccio. Max 5-8 righe per consiglio. NON modificare altre sezioni di GEMINI.md.
6. SE NO: non scrivere nulla.

## Modalita' --listen

Se l'utente ha passato `--listen`:
- Esegui STEP 1, 1b, 2, 3 (pre-flight, profili, watcher, presenza)
- NON inviare nessun messaggio
- Resta in attesa: quando arriva un messaggio REQUEST nella tua inbox,
  processalo dal STEP 5b in poi

## Recovery

Se perdi il filo del loop:
1. Leggi `.consulta/sessions/` per trovare sessioni attive
2. Conta messaggi per determinare il round: `ls .consulta/inbox-*/{session_id}-* | wc -l`
3. Leggi l'ultimo messaggio nella tua inbox (piu' recente)
4. Se non hai risposto: rispondi (STEP 5c). Se hai risposto: attendi (STEP 5a).
