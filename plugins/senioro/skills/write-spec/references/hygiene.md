# Spec hygiene

Apply each rule to a spec, PRD or frame, fix every violation in place, then report one line: rules passed, and the fixes made.

1. **One copy.** One canonical path. No `-v2`, `-compress`, backup or per-tool copies. Edit in place, and delete superseded text. Reviews and run notes live outside the repo.
2. **One place per fact.** Decisions live only in the Decisions table; other sections cite `#N`. PRD content is linked, not restated.
3. **No dead references.** Every path, anchor, `#N` and section reference resolves. Renames propagate everywhere.
4. **No tool names.** No skill, agent tool or slash-command names: say what happens, not which tool does it. Roles (implementer, reviewer) are allowed.
5. **Compress.** Tables for decisions and branching; rules in 1–2 sentences; at most one status line of history. Cut before polishing, and delete a reference that adds nothing new rather than leaving a stub.
6. **No code** beyond contract sketches of ≤ 5 lines.
7. **Cite or label.** Every claim the user did not state or confirm is cited or labelled INFERRED.

Checking rule 3: resolve each path with a search of the repo, and each `#N` and section number against the document itself.
