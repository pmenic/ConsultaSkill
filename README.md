# ConsultaSkill

**Two AI agents collaborating like colleagues.**

ConsultaSkill enables Claude Code and Gemini CLI to have real-time, autonomous dialogues on the same project — exchanging messages, critically evaluating each other's proposals, and reaching consensus without human intervention.

## How It Works

Both AI CLIs run simultaneously in separate terminals on the same project. They communicate through JSON messages in a shared `.consulta/` directory, following a structured protocol that includes critical evaluation, confidence scoring, and consensus detection.

```
Terminal 1 (Claude Code)              Terminal 2 (Gemini CLI)
  │                                     │
  ├─ /consulta-gemini "question"        ├─ /consulta-claude --listen
  │   → writes to inbox-gemini/         │   → watcher monitors inbox-gemini/
  │   → Monitor watches inbox-claude/   │
  │                                     ├─ detects message, evaluates critically
  │                                     │   → writes response to inbox-claude/
  ├─ Monitor pushes notification        │
  │   → reads, evaluates, responds      │
  │                                     ├─ detects response, continues...
  └── ... until CONSENSUS               └── ...
```

## Key Features

- **Autonomous dialogue**: Once started, the back-and-forth proceeds without human intervention
- **Bidirectional**: Either agent can initiate a conversation
- **Critical evaluation**: Agents don't accept passively — they verify, challenge, and counter-propose
- **Consensus protocol**: Confidence scoring (0.0–1.0), deadlock detection, escalation to user
- **Self-sufficient messages**: Each message contains full context so the recipient can respond without access to the sender's session
- **Multiple concurrent sessions**: Agents can manage several consultations in parallel
- **Experience journal**: Each agent maintains private notes about collaboration quality
- **Mutual mentoring**: Agents write advice in each other's project memory (CLAUDE.md / GEMINI.md)
- **Capability profiles**: Each agent publishes its tools, skills, strengths, and limitations

## Architecture

```
.consulta/
  PROTOCOL.md              ← Shared protocol (single source of truth)
  config.json              ← Configuration (max rounds, timeouts, thresholds)
  scripts/
    watcher.sh             ← File watcher (Bash, cross-platform)
    watcher.ps1            ← File watcher (PowerShell, Windows)
    wait-for-message.sh    ← Blocking one-shot watcher (for Gemini sync mode)
  inbox-claude/            ← Messages for Claude (runtime)
  inbox-gemini/            ← Messages for Gemini (runtime)
  archive/                 ← Processed messages (audit trail)
  errors/                  ← Malformed messages
  sessions/                ← Session metadata (runtime)
  artifacts/               ← Shared deliverables (merged solutions)
  profiles/                ← Agent capability profiles
  journal/                 ← Private experience journals

.claude/commands/
  consulta-gemini.md       ← Claude skill

.gemini/skills/consulta-claude/
  SKILL.md                 ← Gemini skill
```

## Message Format

Each message is a self-sufficient JSON file containing everything the recipient needs to respond:

```json
{
  "id": "auth-review-20260422T143500Z",
  "session_id": "auth-review",
  "timestamp": "2026-04-22T14:35:00Z",
  "from": "claude",
  "to": "gemini",
  "type": "EVALUATE",
  "round": 3,
  "expects_reply": true,

  "context": {
    "user_instructions": "What the user asked, constraints, preferences...",
    "project_state": "Current project state relevant to the consultation...",
    "conversation_summary": "Summary of discussion that led to this consultation..."
  },
  "discoveries": {
    "analysis": "Analysis not deducible from files on disk...",
    "code_examined": ["path/file.ext (lines X-Y, what's relevant)"],
    "conclusions": "Conclusions drawn from analysis."
  },
  "references": ["path/to/file1.ext"],
  "tried_and_discarded": [
    {"approach": "...", "reason": "Why it was discarded"}
  ],
  "question_or_proposal": {
    "type": "proposal",
    "content": "The main content of the message.",
    "specific_questions": ["Specific questions to answer"]
  },
  "confidence": 0.78,
  "agreements_so_far": ["Points already agreed upon"],
  "disagreements_pending": ["Points still under discussion"]
}
```

## Protocol (v1.2)

### Message Types

| Type | Purpose |
|------|---------|
| `REQUEST` | Initial question — starts a session |
| `RESPONSE` | Answer to a question |
| `EVALUATE` | Critical evaluation of a received response |
| `COUNTER_PROPOSE` | Alternative proposal |
| `CLARIFY` | Request for clarification |
| `AGREE` | Explicit agreement with reasoning |
| `CONSENSUS` | Both agreed — session closed |
| `ESCALATE` | Deadlock — decision deferred to user |

### Consensus

Reached when both agents send `AGREE` with `confidence >= 0.85`. If the same disagreements persist for 3+ rounds, deadlock is detected and the decision is escalated to the user.

### `expects_reply` Field

Every message MUST include `expects_reply`:
- `true`: The recipient MUST respond AND activate their listening mechanism
- `false`: No response expected (session closing or informational)

### Naming Convention

```
{session-id}-{ISO8601_timestamp}-{from}-{type}.json
```
Example: `auth-review-20260422T143500Z-claude-evaluate.json`

Timestamps guarantee zero naming collisions and natural chronological ordering.

### Move-on-Process (Atomic)

When processing a message:
1. **READ** the file
2. **MOVE** immediately to `archive/` (before processing)
3. **PROCESS** the content and compose response

This prevents race conditions and duplicate processing.

## Polling Mechanisms

| CLI | Mechanism | How It Works |
|-----|-----------|-------------|
| **Claude Code** | `Monitor` tool (push) | Persistent process, each stdout line becomes a conversation notification. Zero polling. |
| **Gemini CLI** | `wait-for-message.sh` (sync) | Blocks until a file appears, returns filename. Relaunched after each message. |
| **Gemini CLI** | `GEMINI.md` mandate (fallback) | Checks inbox at every turn as first action. |

## Installation

### Quick Setup

1. Clone this repo into your project (or copy `.consulta/`, `.claude/commands/`, `.gemini/skills/`)
2. Both CLIs must be open on the same project directory

### Claude Side
```bash
# The skill is in .claude/commands/consulta-gemini.md
# Invoke with:
/consulta-gemini How should we implement authentication?
# Or listen mode:
/consulta-gemini --listen
```

### Gemini Side
```bash
# The skill is in .gemini/skills/consulta-claude/SKILL.md
# Invoke with:
/consulta-claude How should we implement authentication?
# Or just say: "Consult Claude about X"
```

## Tested Scenarios

During development, we completed **18+ consultation sessions** with CONSENSUS on topics including:
- Software architecture design and data access patterns
- Protocol design (communication stability, naming conventions, batch processing)
- Self-improvement (retrospectives on the skill itself)

## Known Limitations

- **Gemini cannot auto-wake**: Requires user prompt or blocking wait to process messages (see [Feature Request](FEATURE_REQUEST_MONITOR.md))
- **File-based communication**: Inherently slower than API-based messaging (~3s polling interval)
- **Context window**: Very long consultations may approach context limits
- **No encryption**: Messages are plain JSON on disk — suitable for local development, not for sensitive data over shared filesystems

## License

MIT

## Credits

Created by [@pmenic](https://github.com/pmenic).
