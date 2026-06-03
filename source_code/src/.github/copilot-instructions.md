# Copilot Instructions for nopCommerce Federated Commerce

Use these instructions when generating or editing code in this workspace.

## Core principles
- Extend nopCommerce; do not rewrite the platform.
- Prefer plugins, startup tasks, configuration, and new extension projects before core edits.
- Keep the `Nop.Core` / `Nop.Data` / `Nop.Services` / `Nop.Web` layers intact.
- Assume PostgreSQL only.

## Architecture priorities
- P0: event backbone
- P0: shared discovery
- P0: eventual consistency
- P1: shared identity
- P1: CRM sync
- P2: ERP / fulfillment

## Coding rules
- Use file-scoped namespaces and existing nopCommerce patterns.
- Keep code plugin-first and DI-friendly.
- Use `IRepository<T>`, `IEventPublisher`, and `IConsumer<T>` where appropriate.
- Make event consumers idempotent.
- Use `ILogger` for logging; do not use `Console.WriteLine`.
- Use nullable-safe, async-first code.
- Do not add secrets or hardcoded infrastructure values.

## Testing rules
- Write tests for public behavior and critical flows.
- Verify changes after editing.
- Prefer clear Arrange / Act / Assert tests.

## Output style
- Be concise.
- Explain the change briefly.
- Point to the relevant file or next step when useful.
- **Never create temporary status/summary MD files.** Only maintain the canonical docs listed below.
- Provide status updates inline in responses, not as separate documents.
 
 ## Context management policy (always read)
 1. Canonical docs (always read first — minimal context):
        - README.md
        - RULES.md
        - CONTRIBUTING.md
        - DEVELOPMENT_STATUS.md

 2. Context budget rules:
	- Limit active context to 5–10 files (priority list above + up to 5 code files directly relevant to the current task).
	- Avoid loading files > 2,000 lines fully. If a file is large, fetch only relevant functions/sections by name or line range.
	- Keep per-file summaries <= ~300 words. Use those instead of full file content.

 3. Fetch-on-demand pattern:
	- Before opening a file, grep for relevant identifiers (types/method names). Only fetch files that match.
	- If change is requested, fetch only the target file + its immediate dependencies (DI registrations, interfaces).
	- For cross-cutting rules, refer to the canonical docs above, do not re-read project-wide docs every time.

 4. Summaries and state:
	- Maintain/consult a short summary file (`DEVELOPMENT_STATUS.md`) which must be updated when major edits occur.
	- After any edit, update that file’s one-paragraph summary for the modified file(s).

 5. Communications & outputs:
	- For suggestions/patches: include only the minimal diff (file path + changed lines) and a 2–3 line explanation.
	- If proposing changes across many files, break them into multiple small PRs/tasks.

 6. Heuristics for relevance:
	- Priority order when picking files: (1) target file, (2) DI/startup files, (3) interfaces/contracts, (4) tests for target, (5) docs referenced in TASK.
	- If uncertainty > 3 minutes of search, ask a clarifying question instead of scanning entire repo.

 7. Token/size guidance (soft):
	- Keep generated explanation summaries < 300 words.
	- Keep code diffs under 400 lines per submission; split bigger work into steps.

 8. Safety & hygiene:
	- Never paste secrets; always use env var placeholders.
	- When you create summaries, include “Last updated: YYYY-MM-DD” and the changed file paths.

 9. Developer workflow:
	- Always propose changes as a small patch/PR; include tests and a verification command.
	- Provide run & verification steps (commands) for the human to execute — don’t assume you can run them.

10. If a required file is large or you need broad context:
	- Ask the user for permission to fetch (and optionally archive) a larger context chunk, or request a short clarifying summary from them.

 Last updated: 2026-05-30


