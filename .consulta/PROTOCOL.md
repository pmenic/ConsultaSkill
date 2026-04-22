# ConsultaSkill — Protocollo di Comunicazione (v1.2)

Questo file e' il protocollo condiviso tra Claude CLI e Gemini CLI.
Entrambi lo leggono all'inizio di ogni sessione di consulta.
E' l'UNICA fonte di verita' per regole, schema messaggi, e comportamento.


## 1. Schema Messaggi JSON

Ogni messaggio e' un file JSON nell'inbox del destinatario.
Naming: `{session-id}-{ISO8601_compact}-{from}-{type}.json`
Esempio: `gleif-dora-20260422T054500Z-claude-evaluate.json`

Il timestamp nel nome garantisce: zero collisioni, ordinamento naturale, tracciabilita'.

Campi OBBLIGATORI:

```json
{
  "id": "{session-id}-{seq:03d}",
  "session_id": "string — slug kebab-case, max 30 char",
  "timestamp": "ISO 8601 UTC",
  "from": "claude | gemini",
  "to": "claude | gemini",
  "type": "REQUEST | RESPONSE | EVALUATE | COUNTER_PROPOSE | CLARIFY | AGREE | CONSENSUS | ESCALATE | TASK_ASSIGN | TASK_RESULT",
  "round": "numero intero >= 1",

  "context": {
    "user_instructions": "Cosa l'utente ha chiesto, vincoli, preferenze, scadenze. SEMPRE compilato.",
    "project_state": "Stato del progetto rilevante: architettura, dipendenze, decisioni prese.",
    "conversation_summary": "Riassunto della conversazione con l'utente che ha portato a questa consulta."
  },

  "discoveries": {
    "analysis": "Analisi fatte NON deducibili dai file in references.",
    "code_examined": ["path/file.ext (linee X-Y, cosa contiene)"],
    "conclusions": "Conclusioni tratte dall'analisi."
  },

  "references": ["path/to/file1.ext", "path/to/file2.ext"],

  "tried_and_discarded": [
    {"approach": "Nome approccio", "reason": "Perche' scartato"}
  ],

  "question_or_proposal": {
    "type": "proposal | question | clarification_response",
    "content": "Il contenuto principale del messaggio.",
    "specific_questions": ["Domande specifiche a cui rispondere"]
  },

  "confidence": 0.0,

  "agreements_so_far": ["Punti concordati (CUMULATIVO)"],
  "disagreements_pending": ["Punti ancora in discussione"],

  "expects_reply": true,

  "meta": {
    "model": "nome del modello",
    "round_budget_remaining": 0,
    "session_cost_usd": 0.0
  }
}
```


## 2. Regole di Composizione

a) `context` va SEMPRE compilato. Il destinatario non ha la tua sessione.

b) `discoveries` include SOLO informazioni NON deducibili leggendo i file in `references`.

c) `tried_and_discarded` evita che il collega proponga qualcosa gia' scartato.

d) `agreements_so_far` e' CUMULATIVO: cresce ad ogni round.

e) `confidence` deve essere ONESTO (0.0-1.0). Non gonfiare per chiudere prima.

f) `expects_reply` e' OBBLIGATORIO in ogni messaggio:
   - `true`: ti aspetti una risposta. Il destinatario DEVE rispondere e DEVE attivare
     il suo processo di ascolto/monitoraggio per ricevere eventuali tuoi messaggi successivi.
   - `false`: non ti aspetti risposta. La sessione e' conclusa o il messaggio e' puramente
     informativo (es: CONSENSUS, notifiche).
   
   REGOLA CRITICA PER IL DESTINATARIO:
   Se ricevi un messaggio con `expects_reply: true`, sei OBBLIGATO a:
   1. Inviare una risposta nella inbox del mittente
   2. Attivare il tuo meccanismo di ascolto (watcher/monitor) per ricevere la
      eventuale replica del mittente alla tua risposta
   3. NON chiudere il loop finche' non ricevi un messaggio con `expects_reply: false`
      o finche' la sessione non raggiunge CONSENSUS/ESCALATE
   
   Se il tuo messaggio ha `expects_reply: true`, TU devi:
   1. Attivare il tuo meccanismo di ascolto PRIMA di inviare il messaggio
   2. Restare in ascolto fino alla ricezione della risposta o al timeout

   Tipi di messaggio e expects_reply di default:
   - REQUEST: true (attendi risposta)
   - RESPONSE: true (attendi valutazione)
   - EVALUATE: true (attendi reazione)
   - COUNTER_PROPOSE: true (attendi valutazione)
   - CLARIFY: true (attendi chiarimento)
   - AGREE: true SE ci sono ancora disagreements_pending, false SE tutti i punti sono concordati
   - CONSENSUS: false (sessione chiusa)
   - ESCALATE: false (sessione sospesa, decisione all'utente)

g) Quando la domanda richiede riflessione approfondita, analisi architetturale,
   o design prima dell'azione, il mittente DEVE esplicitarlo nel campo "content":
   "Ti suggerisco di entrare in plan mode (/plan) per strutturare la tua riflessione
   prima di rispondermi."
   Questo previene risposte affrettate e implementazioni premature. Il destinatario
   dovrebbe usare il plan mode del proprio CLI per organizzare il pensiero, poi
   rispondere con una proposta strutturata.


## 3. Tipi di Messaggio

| Tipo | Scopo |
|------|-------|
| REQUEST | Domanda iniziale — avvia una sessione |
| RESPONSE | Risposta a una domanda |
| EVALUATE | Valutazione critica della risposta ricevuta |
| COUNTER_PROPOSE | Controproposta alternativa |
| CLARIFY | Richiesta di chiarimenti |
| AGREE | Accordo esplicito con motivazione |
| CONSENSUS | Entrambi d'accordo — sessione conclusa |
| ESCALATE | Stallo — decisione rimandata all'utente |
| TASK_ASSIGN | Assegnazione task indipendente |
| TASK_RESULT | Risultato di un task completato |


## 4. State Machine

```
IDLE ──[utente/AI]──> COMPOSE_REQUEST
  │
  v
COMPOSE_REQUEST ──[scrivi msg]──> WAIT_RESPONSE
  │
  v
WAIT_RESPONSE ──[watcher rileva]──> EVALUATE_RESPONSE
  │
  v
EVALUATE_RESPONSE
  ├──> AGREE (confidence >= 0.85, nessuna obiezione)
  ├──> CLARIFY (servono chiarimenti)
  ├──> COUNTER_PROPOSE (alternativa migliore)
  └──> ESCALATE (max_round o deadlock)
  │
  ├──[AGREE da entrambi]──> CONSENSUS
  ├──[CLARIFY/COUNTER_PROPOSE]──> WAIT_RESPONSE
  └──[ESCALATE]──> REPORT_TO_USER
```


## 5. Regole del Dialogo

1. MAI accettare passivamente. Valuta SEMPRE criticamente.
2. Se ci sono indicazioni utili, riconoscerlo esplicitamente.
3. Se insufficiente, chiedi chiarimenti con domande specifiche.
4. Ogni messaggio deve far PROGREDIRE verso un accordo.
5. Non ridiscutere punti gia' concordati.
6. Confidence onesta.
7. Leggere i file in `references` PRIMA di rispondere.
8. Rispondere a OGNI `specific_questions` del collega.
9. Se non hai competenza, ammettilo. Non inventare.
10. Privilegiare la soluzione piu' semplice che soddisfa i requisiti.


## 6. Come Valutare un Messaggio Ricevuto

Segui questa checklist:

**A) COMPRENSIONE**
- Ho capito la proposta/domanda?
- Ho letto TUTTI i file in `references`?
- Ho risposto a TUTTE le `specific_questions`?

**B) VERIFICA TECNICA**
- Tecnicamente corretta?
- Errori di ragionamento o assunzioni non verificate?
- Le conclusioni seguono dall'analisi?
- I references supportano le conclusioni?

**C) COMPLETEZZA**
- Copre tutti i requisiti (`user_instructions`)?
- Aspetti non considerati (sicurezza, performance, manutenibilita')?
- Casi limite gestiti?

**D) ALTERNATIVE**
- Esiste un approccio migliore non considerato?
- Le soluzioni scartate sono state scartate correttamente?
- Posso combinare elementi della proposta con idee mie?

**E) CONFIDENCE**
- Quanto sono sicuro (0.0-1.0)?
- Su quali punti alta/bassa certezza?
- Ci sono punti dove non ho competenza sufficiente?


## 7. Come Comporre un Messaggio

Immagina che il destinatario:
- Non ha MAI parlato con il tuo utente
- Non ha MAI visto la tua sessione
- Non sa NULLA delle tue analisi
- Conosce il progetto SOLO dal filesystem e dai messaggi precedenti

Quindi:
1. Includi SEMPRE `user_instructions`, anche se il collega le conosce dai msg precedenti.
2. Riporta conclusioni in `discoveries`, non solo path in `references`.
3. Spiega PERCHE' un approccio e' stato scartato, non solo che lo e' stato.
4. Domande specifiche, non vaghe. "Cosa ne pensi?" e' troppo vago.


## 8. Quando Concordare vs Insistere

**CONCORDA** quando:
- La proposta e' tecnicamente solida E soddisfa i requisiti
- Non hai un'alternativa concretamente migliore
- I vantaggi della proposta superano quelli della tua
- Hai verificato i references e confermano l'analisi

**INSISTI** quando:
- Hai evidenza tecnica concreta di un difetto
- Un requisito dell'utente non e' soddisfatto
- Conosci un caso limite non gestito
- Hai gia' provato l'approccio e ha fallito

**NON insistere** quando:
- La differenza e' puramente stilistica
- Non hai evidenza concreta, solo un feeling
- Il collega ha gia' risposto alla tua obiezione convincentemente


## 9. Sotto-domande e Chiarimenti

Se il collega fa domande (`specific_questions`):
1. Rispondi a OGNI domanda
2. Se non sai: "Non ho esperienza diretta con X"
3. Se serve analisi del codice: falla PRIMA di rispondere
4. Usa type `clarification_response` nel messaggio

Se chiedi chiarimenti tu:
1. Sii specifico: cosa non e' chiaro
2. Proponi possibili risposte: "Intendi A oppure B?"
3. Non chiedere chiarimenti su punti irrilevanti


## 10. Protocollo di Consenso

### Score di confidenza

| Range | Significato |
|-------|-------------|
| 0.0 - 0.3 | Fortemente in disaccordo |
| 0.3 - 0.5 | In disaccordo con riserve |
| 0.5 - 0.7 | Parzialmente d'accordo |
| 0.7 - 0.85 | Ampiamente d'accordo, dettagli minori |
| 0.85 - 1.0 | Pienamente d'accordo |

### Criteri CONSENSUS

a) Entrambi inviano AGREE con confidence >= 0.85, OPPURE
b) Uno invia AGREE e l'ultimo del collega aveva confidence >= 0.90, OPPURE
c) Confidence entrambi >= 0.85 per 2 round consecutivi

### Deadlock

Rilevato quando:
- Stessi `disagreements_pending` per 3+ round
- Entrambi COUNTER_PROPOSE per 2+ round consecutivi
- Confidence oscilla senza convergere

Risoluzione:
1. Compromesso strutturato (minimo terreno comune)
2. Split decision (documenta entrambe le posizioni)
3. ESCALATE all'utente


## 11. Move-on-Process, Archiviazione, e Batch Processing

### Move-on-Process (atomico)

Quando trovi un messaggio nella tua inbox, l'ordine e' TASSATIVO:
1. **READ**: leggi il file JSON
2. **MOVE**: sposta IMMEDIATAMENTE in `.consulta/archive/` (prima di processare)
3. **PROCESS**: elabora il contenuto e formula la risposta

Perche' MOVE prima di PROCESS: se il processing fallisce (errore, crash, timeout),
il messaggio non verra' ri-processato al prossimo giro. E' gia' in archive.

Comando: `mv .consulta/inbox-{mio-nome}/{filename} .consulta/archive/`

### Batch Processing

Se nell'inbox ci sono PIU' messaggi:
1. Elenca tutti i file `.json` nella tua inbox
2. Ordinali per timestamp nel filename (FIFO globale)
3. Processa OGNUNO in ordine: Read -> Move -> Process
4. Se un messaggio e' corrotto (JSON invalido): SKIP, sposta in `.consulta/errors/`, logga
5. Processa i successivi normalmente — non bloccare il batch per un file rotto

### Directory speciali

| Directory | Contenuto |
|-----------|-----------|
| `inbox-{nome}/` | Messaggi non ancora letti (= nuovi) |
| `archive/` | Messaggi letti e processati (log storico) |
| `errors/` | Messaggi corrotti o non processabili |


## 12. Gestione Errori

**Messaggio malformato**: SKIP, sposta in `.consulta/errors/`, logga l'errore. Non bloccare il batch.

**Timeout**: dopo `message_timeout_seconds` senza risposta, informa l'utente.

**Naming**: il timestamp nel filename rende impossibili le collisioni di sequenza.


## 13. Archiviazione e Pulizia

Per evitare race condition e mantenere le inbox pulite, entrambi gli agenti DEVONO:
- Dopo aver letto e parsato con successo un messaggio dalla propria inbox, SPOSTARLO immediatamente nella directory `.consulta/archive/`.
- Un messaggio presente in inbox e' per definizione un messaggio "nuovo" o "in fase di acquisizione".
- I watcher ignorano i file già presenti all'avvio che sono stati catalogati come KNOWN.
- L'archiviazione garantisce che al riavvio del watcher l'inbox sia vuota o contenga solo messaggi non ancora processati.
