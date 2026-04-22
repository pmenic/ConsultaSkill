# ConsultaSkill — Communication Protocol (v1.2)

This file is the shared protocol between Claude CLI and Gemini CLI.
Both read it at the start of every consultation session.
It is the SINGLE source of truth for rules, message schema, and behavior.


## 1. JSON Message Schema

Each message is a JSON file in the recipient's inbox.
Naming: `{session-id}-{ISO8601_compact}-{from}-{type}.json`
Example: `gleif-dora-20260422T054500Z-claude-evaluate.json`

Timestamps in filenames guarantee: zero collisions, natural ordering, traceability.

REQUIRED fields:

```json
{
  "id": "{session-id}-{timestamp}",
  "session_id": "string — kebab-case slug, max 30 chars",
  "timestamp": "ISO 8601 UTC",
  "from": "claude | gemini",
  "to": "claude | gemini",
  "type": "REQUEST | RESPONSE | EVALUATE | COUNTER_PROPOSE | CLARIFY | AGREE | CONSENSUS | ESCALATE | TASK_ASSIGN | TASK_RESULT",
  "round": "integer >= 1",

  "context": {
    "user_instructions": "What the user asked, constraints, preferences, deadlines. ALWAYS filled.",
    "project_state": "Relevant project state: architecture, dependencies, decisions made.",
    "conversation_summary": "Summary of the conversation with the user that led to this consultation."
  },

  "discoveries": {
    "analysis": "Analysis NOT deducible from files in references.",
    "code_examined": ["path/file.ext (lines X-Y, what it contains)"],
    "conclusions": "Conclusions drawn from the analysis."
  },

  "references": ["path/to/file1.ext", "path/to/file2.ext"],

  "tried_and_discarded": [
    {"approach": "Approach name", "reason": "Why it was discarded"}
  ],

  "question_or_proposal": {
    "type": "proposal | question | clarification_response",
    "content": "The main content of the message.",
    "specific_questions": ["Specific questions to answer"]
  },

  "confidence": 0.0,

  "agreements_so_far": ["Points agreed upon (CUMULATIVE)"],
  "disagreements_pending": ["Points still under discussion"],

  "expects_reply": true,

  "meta": {
    "model": "model name",
    "round_budget_remaining": 0,
    "session_cost_usd": 0.0
  }
}
```


## 2. Composition Rules

a) `context` MUST ALWAYS be filled. The recipient doesn't have your session.

b) `discoveries` includes ONLY information NOT deducible by reading the files in `references`.

c) `tried_and_discarded` prevents the colleague from proposing something already discarded.

d) `agreements_so_far` is CUMULATIVE: it grows with each round.

e) `confidence` must be HONEST (0.0-1.0). Don't inflate to close early.

f) `expects_reply` is MANDATORY in every message:
   - `true`: you expect a response. The recipient MUST reply and MUST activate
     their listening/monitoring mechanism to receive your subsequent messages.
   - `false`: you don't expect a reply. Session is concluded or the message
     is purely informational (e.g., CONSENSUS, notifications).
   
   CRITICAL RULE FOR THE RECIPIENT:
   If you receive a message with `expects_reply: true`, you are OBLIGATED to:
   1. Send a reply to the sender's inbox
   2. Activate your listening mechanism (watcher/monitor) to receive the
      sender's potential reply to your response
   3. Do NOT close the loop until you receive a message with `expects_reply: false`
      or the session reaches CONSENSUS/ESCALATE
   
   If your message has `expects_reply: true`, YOU must:
   1. Activate your listening mechanism BEFORE sending the message
   2. Stay listening until receiving the response or timeout

   Message types and default expects_reply:
   - REQUEST: true (awaiting response)
   - RESPONSE: true (awaiting evaluation)
   - EVALUATE: true (awaiting reaction)
   - COUNTER_PROPOSE: true (awaiting evaluation)
   - CLARIFY: true (awaiting clarification)
   - AGREE: true IF there are still disagreements_pending, false IF all points agreed
   - CONSENSUS: false (session closed)
   - ESCALATE: false (session suspended, decision to user)

g) When the question requires deep reflection, architectural analysis,
   or design before action, the sender MUST make it explicit in "content":
   "I suggest you enter plan mode (/plan) to structure your thinking before replying."
   This prevents hasty responses and premature implementations. The recipient
   should use their CLI's plan mode to organize their thinking, then reply
   with a structured proposal.


## 3. Message Types

| Type | Purpose |
|------|---------|
| REQUEST | Initial question — starts a session |
| RESPONSE | Answer to a question |
| EVALUATE | Critical evaluation of a received response |
| COUNTER_PROPOSE | Alternative proposal |
| CLARIFY | Request for clarification |
| AGREE | Explicit agreement with reasoning |
| CONSENSUS | Both agreed — session closed |
| ESCALATE | Deadlock — decision deferred to user |
| TASK_ASSIGN | Independent task assignment |
| TASK_RESULT | Completed task result |


## 4. State Machine

```
IDLE ──[user/AI]──> COMPOSE_REQUEST
  │
  v
COMPOSE_REQUEST ──[write msg]──> WAIT_RESPONSE
  │
  v
WAIT_RESPONSE ──[watcher detects]──> EVALUATE_RESPONSE
  │
  v
EVALUATE_RESPONSE
  ├──> AGREE (confidence >= 0.85, no objections)
  ├──> CLARIFY (clarifications needed)
  ├──> COUNTER_PROPOSE (better alternative)
  └──> ESCALATE (max_round or deadlock)
  │
  ├──[AGREE from both]──> CONSENSUS
  ├──[CLARIFY/COUNTER_PROPOSE]──> WAIT_RESPONSE
  └──[ESCALATE]──> REPORT_TO_USER
```


## 5. Dialogue Rules

1. NEVER accept passively. ALWAYS evaluate critically.
2. If there are useful insights, acknowledge them explicitly.
3. If insufficient, ask for clarifications with specific questions.
4. Every message must PROGRESS toward agreement.
5. Don't re-discuss points already agreed upon.
6. Honest confidence.
7. Read files in `references` BEFORE responding.
8. Answer EVERY `specific_questions` from the colleague.
9. If you lack expertise, admit it. Don't fabricate.
10. Prefer the simplest solution that satisfies the requirements.


## 6. How to Evaluate a Received Message

Follow this checklist:

**A) COMPREHENSION**
- Did I understand the proposal/question?
- Did I read ALL files in `references`?
- Did I answer ALL `specific_questions`?

**B) TECHNICAL VERIFICATION**
- Technically correct?
- Reasoning errors or unverified assumptions?
- Do conclusions follow from the analysis?
- Do references actually support the conclusions?

**C) COMPLETENESS**
- Covers all requirements (`user_instructions`)?
- Unconsidered aspects (security, performance, maintainability)?
- Edge cases handled?

**D) ALTERNATIVES**
- Is there a better approach not considered?
- Were discarded solutions correctly discarded?
- Can I combine elements of the colleague's proposal with my own ideas?

**E) CONFIDENCE**
- How sure am I (0.0-1.0)?
- On which points high/low certainty?
- Are there points where I lack sufficient expertise?


## 7. How to Compose a Message

Imagine the recipient:
- Has NEVER spoken with your user
- Has NEVER seen your session
- Knows NOTHING about your analyses
- Knows the project ONLY through the filesystem and previous messages

Therefore:
1. ALWAYS include `user_instructions`, even if the colleague knows them from previous messages.
2. Report conclusions in `discoveries`, not just paths in `references`.
3. Explain WHY an approach was discarded, not just that it was.
4. Specific questions, not vague. "What do you think?" is too vague.


## 8. When to Agree vs Insist

**AGREE** when:
- The proposal is technically sound AND satisfies requirements
- You don't have a concretely better alternative
- The proposal's advantages outweigh yours
- You've verified references and they confirm the analysis

**INSIST** when:
- You have concrete technical evidence of a flaw
- A user requirement is not met by the proposal
- You know an edge case that isn't handled
- You've already tried the proposed approach and it failed

**DON'T insist** when:
- The difference is purely stylistic
- You have no concrete evidence, just a feeling
- The colleague has already answered your objection convincingly


## 9. Sub-questions and Clarifications

If the colleague asks questions (`specific_questions`):
1. Answer EVERY question
2. If you don't know: "I have no direct experience with X"
3. If code analysis is needed: do it BEFORE answering
4. Use type `clarification_response` in the message

If you ask for clarifications:
1. Be specific: what exactly is unclear
2. Suggest possible answers: "Do you mean A or B?"
3. Don't ask for clarifications on points irrelevant to the final decision


## 10. Consensus Protocol

### Confidence Score

| Range | Meaning |
|-------|---------|
| 0.0 - 0.3 | Strongly disagree |
| 0.3 - 0.5 | Disagree with reservations |
| 0.5 - 0.7 | Partially agree |
| 0.7 - 0.85 | Broadly agree, minor details to resolve |
| 0.85 - 1.0 | Fully agree |

### CONSENSUS Criteria

a) Both send AGREE with confidence >= 0.85, OR
b) One sends AGREE and the colleague's last confidence was >= 0.90, OR
c) Both confidence >= 0.85 for 2 consecutive rounds

### Deadlock

Detected when:
- Same `disagreements_pending` for 3+ rounds
- Both COUNTER_PROPOSE for 2+ consecutive rounds
- Confidence oscillates without converging

Resolution:
1. Structured compromise (minimum common ground)
2. Split decision (document both positions)
3. ESCALATE to user


## 11. Move-on-Process, Archiving, and Batch Processing

### Move-on-Process (atomic)

When you find a message in your inbox, the order is MANDATORY:
1. **READ**: read the JSON file
2. **MOVE**: IMMEDIATELY move to `.consulta/archive/` (before processing)
3. **PROCESS**: elaborate the content and compose response

Why MOVE before PROCESS: if processing fails (error, crash, timeout),
the message won't be re-processed next time. It's already in archive.

Command: `mv .consulta/inbox-{my-name}/{filename} .consulta/archive/`

### Batch Processing

If there are MULTIPLE messages in the inbox:
1. List all `.json` files in your inbox
2. Sort by timestamp in filename (global FIFO)
3. Process EACH in order: Read -> Move -> Process
4. If a message is corrupt (invalid JSON): SKIP, move to `.consulta/errors/`, log
5. Process the next ones normally — don't block the batch for one broken file

### Special Directories

| Directory | Contents |
|-----------|----------|
| `inbox-{name}/` | Messages not yet read (= new) |
| `archive/` | Read and processed messages (audit trail) |
| `errors/` | Corrupt or unprocessable messages |


## 12. Error Handling

**Malformed message**: SKIP, move to `.consulta/errors/`, log the error. Don't block the batch.

**Timeout**: after `message_timeout_seconds` without response, inform the user.

**Naming**: timestamps in filenames make sequence collisions impossible.


## 13. User Notifications

After EVERY round, print:

```
--- Consultation {session_id} — Round {n} ---
From: {sender}
Type: {message type}
Summary: {1-2 sentences about the received message}
My response: {type} — {1-2 sentences}
My confidence: {score} | Colleague confidence: {score}
Agreements: {n} | Disagreements: {n}
---
```
