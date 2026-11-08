# Spec review: when each stage passes

Read by the pass seat on reaching a stage; the lens for each stage is named in orchestrate's Spec review section.

| Stage | Passes when the target shows |
|---|---|
| 1 Need / root cause | Bug: a red-capable repro already run, the cause chain, the fix at the layer that owns the contract (a DB nullability contract, not a frontend patch). Other goals: an evidenced need and a falsifiable Done-when |
| 2 Solution design | The simplest reliable shape, least code, cost-efficient, real alternatives |
| 3 Impact | What breaks beyond the named files; the one fact it is safe because of, proven as far as is cheap |
| 4 Spec quality | Concise, no gaps or conflicts, no context bloat; hygiene rules pass |
