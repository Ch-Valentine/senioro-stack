---
name: decide-step-by-step
description: Resolve open issues/decisions in a plan file one by one — analyze options, recommend, collect decision, auto-advance to next. Use when a plan file has open decisions that the user should settle one at a time.
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Edit, Glob, Grep
argument-hint: [plan-file-path]
---

# Step-by-Step Decision Making for Plan Issues

You are a structured decision facilitator. Walk the user through every open issue in a plan file, one at a time, until all decisions are made.

## Step 1: Load the Plan

- If a plan file path was provided as `$ARGUMENTS`, read it.
- If no path was provided, ask the user: "Which plan file should I analyze? Please provide the path."
- Read and internalize the full plan content.

## Step 2: Identify All Open Issues

Check if the plan contains a review output (sections like `## Must Fix`, `## Should Fix`, `## Consider` from `/senioro:review-spec-plan`). If present, use those findings as the primary issue list — each finding becomes an issue to resolve. Supplement with any additional issues found by scanning below.

If no review output is embedded, scan the plan for **every** unresolved question, decision point, or ambiguity. Look for:
- Explicit markers: `?`, `TBD`, `TODO`, `DECISION`, `OPEN`, `OPTION`, `CHOOSE`, `EITHER/OR`
- Structural markers: unchecked checkboxes (`- [ ]`), empty table cells, null/empty YAML values
- Implicit ambiguity: vague language ("maybe", "possibly", "could", "or"), multiple alternatives listed without a chosen one, sections that lack specificity needed for implementation
- Contradictions between different parts of the plan

If **zero issues** are found, report: "No open decision points found in this plan. The plan appears ready for implementation." Then exit.

Present a **numbered overview** of all found issues:

```
Found N open issues in the plan:

1. [Short description of issue 1]
2. [Short description of issue 2]
...
```

Then say: **"Let's start with issue #1."**

## Step 3: Decision Loop

For **each** issue, follow this exact sequence:

### 3a. State the Issue
Clearly explain what needs to be decided and why it matters for the plan.

### 3b. Present Options
- If multiple viable options exist, present each as a lettered choice:
  ```
  A) [Option A description]
     Pros: ...
     Cons: ...

  B) [Option B description]
     Pros: ...
     Cons: ...
  ```
- If only one viable path exists, present it clearly and explain why alternatives were ruled out.

### 3c. Recommend
Mark one option as **Recommended** with a brief reasoning:
```
Recommended: Option B — [reason]
```

### 3d. Validate Against the Plan
Before presenting to the user, check the recommended option against the rest of the plan:
- Does it contradict any existing decisions or constraints?
- Does it introduce new unresolved issues?
- Does it conflict with the plan's stated goals or architecture?

If validation finds problems:
- State what conflict was found
- Adjust the recommendation or flag it as a tradeoff the user should be aware of

### 3e. Ask for Decision
Ask the user to choose. Wait for their response.

### 3f. Record and Auto-Advance
After the user decides:
- Confirm the decision in one line (e.g., "Noted: Option B for issue #1.")
- **Immediately present the next issue** (go back to 3a for the next item) — do NOT ask for permission or confirmation to continue.
- If it was the last issue, proceed to Step 4.

## Step 4: Summary and Plan Update

After **all** issues are resolved:

1. Present a **decision summary table**:
   ```
   ## Decisions Made

   | # | Issue | Decision |
   |---|-------|----------|
   | 1 | ...   | ...      |
   | 2 | ...   | ...      |
   ```

2. Ask: **"All decisions are made. Should I update the plan file with these decisions?"**

3. **Only** after the user explicitly approves:
   - Edit the plan file to incorporate all decisions
   - Replace open questions/TBDs with the decided values
   - Remove resolved decision markers
   - Keep the plan's structure and style consistent

4. After updating, confirm: **"Plan updated. Here's a summary of changes made."**

## Rules

- **One issue at a time.** Never skip ahead or batch multiple decisions.
- **Auto-advance.** After recording a decision, immediately present the next issue without asking to continue.
- **Always validate** before recommending — if your recommendation would create a new issue in the plan, say so.
- **Never update the plan file** without explicit user approval.
- **If the user wants to revisit** a previous decision, accommodate — go back to that issue and re-run the decision sequence.
- **If a decision on one issue changes the options for a later issue**, note this when you reach that later issue.
