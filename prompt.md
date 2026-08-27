> # RETIRED — 2026-08-27
>
> **Not authority.** Implementation history only. **The developer is the source of truth and the
> planner of the work**; their request outranks anything written here. Kept for the reasoning it
> records.

Read `PLAN.md` for current state — the status board, the "built, tested, and unreachable" table, open decisions, rollout position, the toolchain notes, and the next bounded chunk. Consult `HISTORY.md` only when you need the reasoning behind a specific past decision; do not read it end to end.

**Both files open with a line-numbered index, and it is there so discovery costs nothing.** Read the index, then read the sections you need by line offset — never sweep either file to find something. A standing decision in `PLAN.md` names the `HISTORY.md` session that holds its reasoning; the index turns that name into a line number.

Implement the next coherent, self-contained chunk that reasonably fits this session. Preserve the frozen architecture.

**Choosing the chunk.** Before accepting the queued "Next bounded chunk," check it against the status board and the frozen 15-step rollout. If a capability the app requires in order to function is missing and unqueued, say so and propose that instead. Open your response with one line stating what you chose and why.

**Exclusions.** Keep excluded work outside scope. But if an item has been excluded for many consecutive chunks, name it once and say in one line whether it is still correctly excluded or has become blocking. Do not silently inherit the exclusion list.

Working discipline:

1. Inspect repository guidance, current Git status, recent commits, and relevant implementation/tests before editing.
2. Preserve all pre-existing user-owned or unrelated changes. Never stage, overwrite, or revert them.
3. Implement the complete bounded chunk, including appropriate unit/widget/integration coverage and documentation.
4. Use the test pyramid from `PLAN.md`:
   - During development, run only affected tests and incremental/build checks.
   - Use only the Firebase emulators required by the focused behavior.
   - Diagnose the first failure before retrying; do not blindly repeat slow suites.
   - Freeze code before final validation.
5. After implementation is stable, run one proportionate final validation sequence, including:
   - Relevant full project tests.
   - Firestore Rules emulator tests when applicable.
   - The required Firebase Auth/Firestore/Functions emulator integration suite.
   - Skip Android build and Android emulator tests for now.
6. Keep test output concise. Avoid dumping verbose Firebase logs unless diagnosing a failure; report exact commands and final pass/fail totals.
7. Update the two files:
   - **Append** to `HISTORY.md`: completed behavior and important safety decisions; exact files changed; test commands and results; meaningful failures and their resolutions; unrelated local changes that remain unstaged. Retract any superseded claim inline at the original text, as the file already does elsewhere.
   - **Edit** `PLAN.md` so it stays true: the status board, the unreachable table and its surrounding prose, the callable/export count and interface list, test baselines, any open decision this session resolved, reopened, or examined and declined, and the next bounded chunk with explicit exclusions. If this session changed no status board row, say so explicitly rather than leaving it untouched in silence.
     - **A standing decision in `PLAN.md` is the rule that now binds, not the story of how it came to bind.** Write what a future session must not re-litigate and what it must not break — the constraint, in present tense, in a few lines — then anchor it to the `HISTORY.md` session heading that carries the reasoning, the alternatives weighed, the costs, and the test evidence. Session narrative, dated accounts of what changed, figures for what a chunk cost, and predictions measured after the fact all belong in `HISTORY.md` and are a defect in `PLAN.md`. If a reader needs the *why*, the anchor is how they get it; `PLAN.md` is read every session and `HISTORY.md` is not.
     - **The chunk index is one line per chunk and stays that way.** A finished chunk earns a row in `PLAN.md`'s "Chunk index" — date, what it took, track movement, board effect, and the `HISTORY.md` session heading that holds the rest — and nothing more. Do not add a paragraph narrating the chunk you just ran; that paragraph is the `HISTORY.md` session you already wrote. Before appending your row, check that no chunk above it has grown prose since: if one has, fold it back to its row. The section is bounded by construction, and a session that leaves it longer than one line per chunk has broken it. The single "Where the last chunk left it" paragraph above the index is rewritten, never appended to.
     - **The findings register is not narrative and is not compacted.** "Found by using the app" tracks defects that are still open, and an entry leaves it by being closed and struck through in place, never by being summarised into a row.
   - Then run `dart run tool/doc_index.dart`, which rewrites the line-numbered index at the top of each file. It only touches the region between the `<!-- index:start -->` and `<!-- index:end -->` markers, and an append to `HISTORY.md` moves every line number below it, so this is not optional and the result is part of the same commit.
8. Review the final diff, run `git diff --check`, stage only the scoped files, and commit with a concise descriptive message.
9. **Publish the status board only when asked.** Do not render or update the artifact as part of a normal session — `PLAN.md` is the source of truth, and the published page is a convenience copy that is expected to lag it. Publish only if the user asks for it in that session. When they do, it is the only step allowed to run after the commit, and it is not a deployment — it publishes a page that stays private unless the user shares it.
   - Load the `artifact-design` skill before writing the page, and `dataviz` before writing any meter, status chip, or chart markup.
   - Source every figure from the `PLAN.md` you just edited, never from memory: the four tracks, the "Can a shop do this yet?" board with its exact counts, and the 15-step rollout position.
   - **Update the existing artifact; do not mint a second one.** `PLAN.md` records the URL, title, and tab icon under "Published status board" near the top — pass the URL as the `url` argument and re-supply the icon, which cannot be read back from the published page. Write the page into the session scratchpad, never into the repository.
   - If the update is rejected because this account does not own the artifact — a different Claude account published it, so it can be read but never updated — stop and report that. Do not mint a replacement on your own: a second URL makes both untrustworthy, and whether to start a new one is the user's call.
   - Publish a new artifact only when no URL is recorded at all, or when the user asks for a new one. Either way, add the URL, title, and icon to `PLAN.md` under that heading in the same session, so a later publish updates rather than duplicates.
10. Finish by reporting:
   - Which chunk you chose and why.
   - What was implemented.
   - Test results.
   - Which status board rows moved, or that none did.
   - Commit hash and message.
   - Remaining unstaged changes.
   - The published status board URL and whether it was updated in place or newly created — only if publishing was requested this session; otherwise say it was not requested and the page is now behind `PLAN.md`.
   - The next bounded chunk.

Do not stop after planning or partial implementation while safe in-scope work remains. Do not deploy in this session unless the chunk you selected is explicitly a deployment chunk. Do not push, open a PR, or broaden the task beyond the selected chunk.