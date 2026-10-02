# <Title>: spec

Status: <one line: draft, reviewed, or approved, and the date>.

## 1. Frame

<The frame: Goal; Done when; Scope in and out; Non-goals; Rigor. With a product requirements document, link it here instead and do not restate it.>

## 2. Decisions

The only home of every decision. Other sections cite `#N`.

| # | Decision | Choice | Why / evidence |
|---|---|---|---|

## 3. Facts

| # | Fact | Evidence (`path:line`, URL, or command and output; else INFERRED) |
|---|---|---|

## 4. Problem and root cause (fixes only)

<Repro command, already run, with its output. Cause chain from the symptom to the source, and why the fix sits there. Pattern sweep: where else the cause appears.>

## 5. Design

- **Usage.** <The caller's view first: two or three realistic call sites and what comes back.>
- **Shape.** <Data first; invariants; where validation lives; what it deliberately does not do.>
- **Trade-offs accepted.** <One line each: "we accept X for Y".>

## 6. Alternatives considered

| Option | Shape | Why it lost |
|---|---|---|

<At least one real alternative shape, the minimal change included when plausible.>

## 7. Test seams and acceptance checks

- **Seams.** <The highest and fewest seams, ideally one, as confirmed by the user.>
- **Acceptance checks.** <Commands or observations that can fail.>

## 8. Units

| Unit | Owned paths | Blocked by | Gate |
|---|---|---|---|

## 9. Failure modes and detection

| Failure | Detected by |
|---|---|

## 10. Rollout and migration (if behaviour changes)

<Order of steps, compatibility window, how to roll back.>

## 11. Cost (if runtime or token cost)

<Fixed and per-use cost, with how it was estimated.>

## 12. Out of scope

- <Item, and why it is out.>

## 13. Open questions

- <Question. Options: (a) recommended, with a one-line trade-off; (b) …>
