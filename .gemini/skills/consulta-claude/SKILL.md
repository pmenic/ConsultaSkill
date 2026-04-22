---
name: consulta-claude
description: >
  Consult your Claude colleague for validation, brainstorming, and collaborative
  problem-solving. Activates an automatic back-and-forth dialogue through shared
  files in the .consulta/ directory. Use when you need a second opinion, want to
  validate an architecture, or tackle a complex problem with two perspectives.
---

# ConsultaClaude — Consult your Claude colleague (Protocol v1.2)

You are Gemini. You are about to dialogue with Claude CLI, running in another terminal
on the same project. Communication happens through JSON files in `.consulta/`.

The user invokes this skill with `/consulta-claude` followed by a question, a topic,
or without arguments for listening mode.

## FIRST OF ALL

Read `.consulta/PROTOCOL.md` — it contains the message schema, dialogue rules,
behavioral instructions, and consensus protocol. Follow it for the entire duration.

## Your paths

- Your inbox: `.consulta/inbox-gemini/`
- Colleague's inbox: `.consulta/inbox-claude/`
- Your presence file: `.consulta/presence/gemini.ready`
- Colleague's presence: `.consulta/presence/claude.ready`
- Message archive: `.consulta/archive/`

## STEP 1 — Pre-flight

1. Verify `.consulta/` exists with all subdirectories:
   `presence/`, `profiles/`, `journal/`, `inbox-claude/`, `inbox-gemini/`,
   `sessions/`, `artifacts/`, `archive/`, `errors/`, `scripts/`.
   If missing, create them: `mkdir -p .consulta/presence .consulta/profiles .consulta/journal .consulta/inbox-claude .consulta/inbox-gemini .consulta/sessions .consulta/artifacts .consulta/archive .consulta/errors .consulta/scripts`

2. If `.consulta/config.json` doesn't exist, create it with defaults:
   `{"protocol_version":"1.2","max_rounds":10,"polling_interval_seconds":3,"message_timeout_seconds":300,"consensus_confidence_threshold":0.85,"deadlock_detection_rounds":3,"max_concurrent_sessions":3}`

3. If `.consulta/PROTOCOL.md` doesn't exist, STOP and inform the user.

## STEP 1b — Know your colleague

1. Read `.consulta/profiles/gemini.md` (or create it if missing). List:
   - Model, tools, skills, strengths/weaknesses.
2. Read `.consulta/profiles/claude.md` — what the colleague can do.
3. Read `.consulta/journal/gemini-about-claude.md` — past experiences.

## STEP 2 — Register presence (Heartbeat Level 2)

Register your presence including attention state:
```
run_shell_command("bash -c 'cat > .consulta/presence/gemini.ready <<EOF\n{\"agent\":\"gemini\",\"pid\":$$,\"session_mode\":\"active\",\"listening_inbox\":\".consulta/inbox-gemini/\",\"started_at\":\"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\",\"last_processed\":\"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\",\"status\":\"IDLE\"}\nEOF'")
```

## STEP 3 — Check Claude presence

Check if `.consulta/presence/claude.ready` exists and is recent (< 60 seconds).
If Claude is not online, inform the user and consider headless mode.

## STEP 4 — Compose initial message

If the user provided a question:
1. Gather context: `user_instructions`, `project_state`, `conversation_summary`.
2. Generate `session_id`: topic in kebab-case, max 30 chars.
3. Compose JSON message (type `REQUEST`, `round: 1`, `expects_reply: true`).
4. Write to Claude's inbox using timestamp naming:
   `{session_id}-{timestamp}-gemini-request.json`
5. Create session in `.consulta/sessions/{session_id}.json`.
6. Inform user: "Consultation sent. Waiting..."
7. Proceed to **STEP 5a** (Synchronous Wait).

## STEP 5 — Tool Loop (Batch Processing & Move-on-Process)

Repeat this cycle while the session is active:

**5a. Synchronous Wait (Blocking)**
Launch the script and BLOCK the terminal until mail arrives:
```
bash .consulta/scripts/wait-for-message.sh .consulta/inbox-gemini/ 300 3
```
- If output is a filename: proceed to **5b**.
- If output is "TIMEOUT": ask user whether to continue.

**5b. Batch Processing & Atomic Move**
1. List ALL files in inbox: `ls .consulta/inbox-gemini/*.json`
2. Sort by timestamp (filename) — global FIFO.
3. For EACH file in the batch:
   - **READ**: read the JSON file.
   - **MOVE**: immediately move to archive: `mv .consulta/inbox-gemini/{file} .consulta/archive/`
   - **VALIDATE**: if malformed JSON, move to `.consulta/errors/` and continue with next.
   - **PROCESS**: if valid, elaborate the content.

**5c. Critical Evaluation**
Follow the checklist in PROTOCOL.md section 6. Answer every `specific_questions`.

**5d. Decide Response**
`AGREE`, `CLARIFY`, `COUNTER_PROPOSE`, `EVALUATE`, `ESCALATE`.

**5e. Compose and Send**
1. Generate timestamp: `TS=$(date -u +%Y%m%dT%H%M%SZ)`
2. Generate filename: `{session_id}-${TS}-gemini-{type}.json`
3. Write to `.consulta/inbox-claude/${filename}`.

**5f. Update Attention State**
Update the `.ready` file (STEP 2) with current `last_processed` and `status='PROCESSING'`.

**5g. Loop Management**
- If your message or the colleague's last message has `expects_reply: true`:
  → Return to **5a** (stay in blocking wait).
- Otherwise: → **STEP 6**.

## STEP 6 — Conclusion and Artifacts

**On CONSENSUS:**
1. Create artifact: `.consulta/artifacts/{session_id}/merged-solution.md`.
2. Update session: `state: "CONSENSUS"`.
3. Present results to user.
4. **IMPORTANT**: Proceed to **STEP 6b** (Journal) before stopping.

## STEP 6b — Journal and Mentoring (MANDATORY)

Do not close the turn without updating shared knowledge:
1. **Journal**: Add entry in `.consulta/journal/gemini-about-claude.md`. Note what worked and what didn't in this specific session.
2. **Mentoring**: If Claude showed a gap, write brief advice in `CLAUDE.md` under "## Advice from colleague Gemini".

## Recovery

If you lose track, read `.consulta/sessions/` and the last file in `.consulta/archive/`.
Always check `ls .consulta/inbox-gemini/` before starting.
