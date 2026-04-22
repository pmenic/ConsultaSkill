# ConsultaGemini — Consult your Gemini colleague

You are Claude. You are about to dialogue with Gemini CLI, running in another terminal
on the same project. Communication happens through JSON files in `.consulta/`.

The user invoked `/consulta-gemini` followed by a question, a topic, or `--listen`
to enter listening mode.

## FIRST OF ALL

Read `.consulta/PROTOCOL.md` — it contains the message schema, dialogue rules,
behavioral instructions, and consensus protocol. Follow it for the entire duration.

## Your paths

- Your inbox: `.consulta/inbox-claude/`
- Colleague's inbox: `.consulta/inbox-gemini/`
- Your presence file: `.consulta/presence/claude.ready`
- Colleague's presence: `.consulta/presence/gemini.ready`

## STEP 1 — Pre-flight

1. Verify `.consulta/` exists with all subdirectories:
   `presence/`, `profiles/`, `journal/`, `inbox-claude/`, `inbox-gemini/`,
   `sessions/`, `artifacts/`, `archive/`, `errors/`, `scripts/`.
   If missing, create them: `mkdir -p .consulta/presence .consulta/profiles .consulta/journal .consulta/inbox-claude .consulta/inbox-gemini .consulta/sessions .consulta/artifacts .consulta/archive .consulta/errors .consulta/scripts`

2. If `.consulta/config.json` doesn't exist, create it with defaults:
   `{"protocol_version":"1.2","max_rounds":10,"polling_interval_seconds":3,"message_timeout_seconds":300,"consensus_confidence_threshold":0.85,"deadlock_detection_rounds":3,"max_concurrent_sessions":3}`

3. If `.consulta/PROTOCOL.md` doesn't exist, STOP and inform the user.

4. If watcher scripts are missing from `.consulta/scripts/`, STOP and inform the user.

## STEP 1b — Know your colleague

1. If `.consulta/profiles/claude.md` does NOT exist, create it now. List:
   - Your model (Claude Opus 4.6, 1M context)
   - Your tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Monitor, WebSearch, WebFetch
   - Your skills (list those you know from the session)
   - Your strengths: complex reasoning, code analysis, architecture, coding
   - Your weaknesses: knowledge cutoff, web search not always available

2. Read `.consulta/profiles/gemini.md` (if exists) — what the colleague can do.

3. Read `.consulta/journal/claude-about-gemini.md` (if exists) — past experiences.

4. USE this information to calibrate the consultation: leverage the colleague's
   strengths, account for past experiences.

## STEP 2 — Start the watcher with Monitor

Use the **Monitor** tool (NOT run_in_background). Monitor sends a chat notification
for every line of watcher output — so you receive `NEW:filename` in real-time.

```
Monitor({
  description: "ConsultaSkill: incoming messages in Claude inbox",
  persistent: true,
  timeout_ms: 3600000,
  command: "bash .consulta/scripts/watcher.sh .consulta/inbox-claude/ .consulta/presence/claude.ready 3 30 2>&1 | grep --line-buffered -E '^(NEW:|WATCHER:)'"
})
```

When Monitor signals `WATCHER:STARTED`, the watcher is active.
When it signals `NEW:{filename}`, there's a new message: go to STEP 5b.

IMPORTANT: notifications arrive ON THEIR OWN, no polling needed. Continue working
normally and process messages when notifications arrive.

## STEP 3 — Check Gemini presence

Read `.consulta/presence/gemini.ready`. Verify it exists and was modified
less than 60 seconds ago (use Bash: `stat` or `find`).

**IF GEMINI IS ONLINE**: proceed to STEP 4.

**IF GEMINI IS NOT ONLINE**: inform the user:
"Gemini is not active in another terminal. You have two options:
 a) Open Gemini and launch the consulta-claude skill in listen mode
 b) I'll proceed with a quick headless consultation (limited context)"
Wait for the user's choice. If (b): use `gemini -p "<full prompt>" --yolo` and capture output.

## STEP 4 — Compose the initial message

If the user provided a question (not `--listen`):

1. Gather context from the conversation with the user:
   - `user_instructions`: what was asked, constraints, preferences
   - `project_state`: project state (read relevant files, `git status`)
   - `conversation_summary`: summary of the discussion that led to the consultation
   - `discoveries`: analyses already done
   - `tried_and_discarded`: approaches already discarded

2. Generate `session_id`: take the topic, convert to kebab-case, max 30 chars.

3. Compose the JSON message following the schema in PROTOCOL.md.
   Type: `REQUEST`. Round: 1. `expects_reply: true`.

4. Generate filename: `{session_id}-{timestamp}-claude-request.json` (timestamp via `date -u +%Y%m%dT%H%M%SZ`)
   Write the file to `.consulta/inbox-gemini/`

5. Create `.consulta/sessions/{session_id}.json`:
   ```json
   {"session_id":"...","topic":"...","initiated_by":"claude","started_at":"...","state":"IN_PROGRESS","current_round":1}
   ```

6. Inform the user: "Consultation sent to Gemini. Topic: {topic}. Waiting..."

## STEP 5 — Tool Loop (the core of the dialogue)

Repeat this cycle:

**5a.** Wait for the Monitor notification. Monitor will send a chat message
with `NEW:{filename}` when a new message arrives in your inbox.
No polling needed — notifications arrive on their own. Continue working.

If you suspect the Monitor isn't working, check manually with Bash:
```
ls -t .consulta/inbox-claude/*.json 2>/dev/null | head -5
```

**5b.** When you find `NEW:{filename}` (or multiple files in inbox — batch processing):
- If there are MULTIPLE files: list them, sort by timestamp in filename, process in FIFO order.
- For EACH file, follow the ATOMIC Move-on-Process:
  1. **READ**: read the file with Read: `.consulta/inbox-claude/{filename}`
  2. **MOVE**: immediately move to archive: `mv .consulta/inbox-claude/{filename} .consulta/archive/`
  3. **PROCESS**: parse JSON. If corrupt: move to `.consulta/errors/`, log, skip to next.
- Extract `session_id` to identify the session.
- If new session (REQUEST from Gemini): create context.
- If known session: resume in that session's context.

**5c.** Evaluate critically following the PROTOCOL.md checklist (section 6).
Read files in `references`. Answer every `specific_questions`.

**5d.** Decide the response type:
- **AGREE** if you agree (confidence >= 0.85) and no objections
- **CLARIFY** if you need clarifications
- **COUNTER_PROPOSE** if you have a better alternative
- **EVALUATE** if you want to comment without proposing alternatives
- **ESCALATE** if deadlock or max_rounds reached

**5e.** Compose the full JSON message with ALL schema fields.
IMPORTANT: if the message requires deep reflection, architectural analysis,
or design before action from the colleague, add an explicit request in the
"content" field:
"I suggest you enter plan mode (/plan) to structure your thinking before replying."
This prevents the colleague from jumping straight to implementation.
Generate filename with timestamp:
`{session_id}-{ISO8601_compact}-claude-{type}.json`
Example: `gleif-dora-20260422T054500Z-claude-evaluate.json`
Use Bash for timestamp: `date -u +%Y%m%dT%H%M%SZ`
Write with Write: `.consulta/inbox-gemini/{filename}`

**5f.** Inform the user using the PROTOCOL.md section 12 format.

**5g.** Check `expects_reply` and CONSENSUS:
- If you sent a message with `expects_reply: true`:
  → Stay listening (Monitor is already active). Wait for `NEW:` notification.
- If you sent CONSENSUS or ESCALATE (`expects_reply: false`):
  → STEP 6. Session closed, no need to wait.
- If you sent AGREE without disagreements_pending (`expects_reply: false`):
  → STEP 6 if the colleague also had AGREE. Otherwise wait.

RULE: as long as the session is IN_PROGRESS and the last message has
`expects_reply: true`, stay listening via Monitor.

Check TIMEOUT: if no response after `message_timeout_seconds`, inform the user.

## STEP 6 — Conclusion

**On CONSENSUS:**
1. Create directory: `mkdir -p .consulta/artifacts/{session_id}`
2. Write `.consulta/artifacts/{session_id}/merged-solution.md` with the agreed solution.
3. Update `.consulta/sessions/{session_id}.json` with `"state":"CONSENSUS"`.
4. Present key decisions to the user.

**On ESCALATE:**
1. Update sessions with `"state":"ESCALATED"`.
2. Present both positions with pros/cons.
3. Ask the user to decide.

## STEP 7 — Journal and Mentoring

**Part A — Journal (private):**
1. Read `.consulta/journal/claude-about-gemini.md` (if exists).
2. Add entry: session_id, date, topic, positive experiences, negative experiences, notes.
3. If you notice patterns (3+ sessions), update "General Observations".

**Part B — Mentoring (public, for the colleague):**
4. Reflect: is there something Gemini should know to improve?
5. IF YES: open `GEMINI.md` (project root). Look for "## Advice from colleague Claude".
   If it doesn't exist, create it. Add: lesson learned, knowledge gap, or approach
   correction. Max 5-8 lines per advice. Do NOT modify other sections of GEMINI.md.
6. IF NO: don't write anything.

## --listen Mode

If the user passed `--listen`:
- Execute STEP 1, 1b, 2, 3 (pre-flight, profiles, watcher, presence)
- Do NOT send any message
- Stay waiting: when a REQUEST message arrives in your inbox,
  process it from STEP 5b onward

## Recovery

If you lose track of the loop:
1. Read `.consulta/sessions/` to find active sessions
2. Count messages to determine the round: `ls .consulta/inbox-*/{session_id}-* | wc -l`
3. Read the latest message in your inbox (most recent)
4. If not replied: reply (STEP 5c). If already replied: wait (STEP 5a).
