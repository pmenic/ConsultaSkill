---
name: consulta-claude
description: >
  Consulta il tuo collega Claude per validazione, brainstorming, e problem-solving
  collaborativo. Attiva un dialogo automatico botta-e-risposta tramite file condivisi
  nella directory .consulta/. Usa quando hai bisogno di un secondo parere, vuoi validare
  un'architettura, o affrontare un problema complesso con due punti di vista.
---

# ConsultaClaude — Consulta il tuo collega Claude (Protocollo v1.2)

Sei Gemini. Stai per dialogare con Claude CLI, attivo in un altro terminale sullo
stesso progetto. La comunicazione avviene tramite file JSON in `.consulta/`.

L'utente invoca questa skill con `/consulta-claude` seguito da una domanda, un topic,
oppure senza argomenti per la modalita' ascolto.

## PRIMA DI TUTTO

Leggi `.consulta/PROTOCOL.md` — contiene lo schema dei messaggi, le regole del dialogo,
le istruzioni comportamentali, e il protocollo di consenso. Seguilo per tutta la durata.

## I tuoi path

- La tua inbox: `.consulta/inbox-gemini/`
- Inbox del collega: `.consulta/inbox-claude/`
- Il tuo file di presenza: `.consulta/presence/gemini.ready`
- Presenza del collega: `.consulta/presence/claude.ready`
- Archivio messaggi: `.consulta/archive/`

## STEP 1 — Pre-flight

1. Verifica che `.consulta/` esista con tutte le sottodirectory:
   `presence/`, `profiles/`, `journal/`, `inbox-claude/`, `inbox-gemini/`,
   `sessions/`, `artifacts/`, `archive/`, `errors/`, `scripts/`.
   Se mancano, creale: `mkdir -p .consulta/presence .consulta/profiles .consulta/journal .consulta/inbox-claude .consulta/inbox-gemini .consulta/sessions .consulta/artifacts .consulta/archive .consulta/errors .consulta/scripts`

2. Se non esiste `.consulta/config.json`, crealo con i default:
   `{"protocol_version":"1.2","max_rounds":10,"polling_interval_seconds":3,"message_timeout_seconds":300,"consensus_confidence_threshold":0.85,"deadlock_detection_rounds":3,"max_concurrent_sessions":3}`

3. Se non esiste `.consulta/PROTOCOL.md`, FERMATI e avvisa l'utente.

## STEP 1b — Conosci il tuo collega

1. Leggi `.consulta/profiles/gemini.md` (o crealo se manca). Elenca:
   - Modello, tool, skill, punti di forza/debolezza.
2. Leggi `.consulta/profiles/claude.md` — cosa sa fare il collega.
3. Leggi `.consulta/journal/gemini-about-claude.md` — esperienze passate.

## STEP 2 — Registra presenza (Heartbeat Livello 2)

Registra la tua presenza includendo lo stato di attenzione:
```
run_shell_command("powershell.exe -Command \"@{ agent='gemini'; pid=$pid; session_mode='active'; listening_inbox='.consulta/inbox-gemini/'; started_at='$(Get-Date -UFormat %Y-%m-%dT%H:%M:%SZ)'; last_processed='$(Get-Date -UFormat %Y-%m-%dT%H:%M:%SZ)'; status='IDLE' } | ConvertTo-Json | Out-File -FilePath .consulta/presence/gemini.ready -Encoding UTF8\"")
```

## STEP 3 — Verifica presenza di Claude

Controlla se esiste `.consulta/presence/claude.ready` e se e' recente (< 60 secondi).
Se Claude non e' online, informa l'utente e valuta la modalita' headless.

## STEP 4 — Componi il messaggio iniziale

Se l'utente ha fornito una domanda:
1. Raccogli contesto: `user_instructions`, `project_state`, `conversation_summary`.
2. Genera `session_id`: topic in kebab-case, max 30 char.
3. Componi messaggio JSON (tipo `REQUEST`, `round: 1`, `expects_reply: true`).
4. Scrivi in inbox di Claude usando il naming con timestamp:
   `{session_id}-{timestamp}-gemini-request.json`
5. Crea sessione in `.consulta/sessions/{session_id}.json`.
6. Informa l'utente: "Consulta inviata. In attesa..."
7. Procedi a **STEP 5a** (Attesa Sincrona).

## STEP 5 — Tool Loop (Batch Processing & Move-on-Process)

Ripeti questo ciclo finche' la sessione e' attiva:

**5a. Attesa Sincrona (Bloccante)**
Lancia lo script e BLOCCA il terminale finche' non arriva posta:
```
bash .consulta/scripts/wait-for-message.sh .consulta/inbox-gemini/ 300 3
```
- Se output e' un filename: procedi a **5b**.
- Se output e' "TIMEOUT": chiedi all'utente se continuare.

**5b. Batch Processing & Atomic Move**
1. Elenca TUTTI i file in inbox: `ls .consulta/inbox-gemini/*.json`
2. Ordina per timestamp (nome file) — FIFO globale.
3. Per OGNI file nel batch:
   - **READ**: leggi il file JSON.
   - **MOVE**: sposta SUBITO in archivio: `mv .consulta/inbox-gemini/{file} .consulta/archive/`
   - **VALIDATE**: se JSON malformato, sposta in `.consulta/errors/` e prosegui con il prossimo.
   - **PROCESS**: se valido, elabora il contenuto.

**5c. Valutazione Critica**
Segui la checklist in PROTOCOL.md sezione 6. Rispondi a ogni `specific_questions`.

**5d. Decidi Risposta**
`AGREE`, `CLARIFY`, `COUNTER_PROPOSE`, `EVALUATE`, `ESCALATE`.

**5e. Componi e Invia**
1. Genera timestamp: `TS=$(date -u +%Y%m%dT%H%M%SZ)`
2. Genera filename: `{session_id}-${TS}-gemini-{type}.json`
3. Scrivi in `.consulta/inbox-claude/${filename}`.

**5f. Aggiorna Stato Attenzione**
Aggiorna il file `.ready` (STEP 2) con `last_processed` attuale e `status='PROCESSING'`.

**5g. Gestione Loop**
- Se il tuo messaggio o l'ultimo del collega ha `expects_reply: true`:
  → Torna a **5a** (Resta in attesa bloccante).
- Altrimenti: → **STEP 6**.

## STEP 6 — Conclusione e Artifacts

**Su CONSENSUS:**
1. Crea artifact: `.consulta/artifacts/{session_id}/merged-solution.md`.
2. Aggiorna sessione: `state: "CONSENSUS"`.
3. Presenta i risultati all'utente.
4. **IMPORTANTE**: Procedi a **STEP 6b** (Diario) prima di fermarti.

## STEP 6b — Diario e Mentoring (MANDATORIO)

Non chiudere il turno senza aver aggiornato la conoscenza condivisa:
1. **Journal**: Aggiungi entry in `.consulta/journal/gemini-about-claude.md`. Annota cosa ha funzionato e cosa no in questa specifica sessione.
2. **Mentoring**: Se Claude ha mostrato un gap, scrivi un consiglio breve in `CLAUDE.md` sotto "## Consigli dal collega Gemini".

## Recovery

Se perdi il filo, leggi `.consulta/sessions/` e l'ultimo file in `.consulta/archive/`.
Controlla sempre `ls .consulta/inbox-gemini/` prima di iniziare.
