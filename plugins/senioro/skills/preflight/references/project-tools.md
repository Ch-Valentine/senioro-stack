# Project tools: detection

How to find the gates, static-analysis tools, AI reviewers and services a project uses. Read by the preflight check and the pre-PR loop. Detect; never assume.

## Rules

- Only tools the project configures or documents count. A tool installed on the machine but absent from the project's files is not the project's tool: running it could send code to a service the project does not use.
- Look in the order below. A later source adds tools; it never overrides a command an earlier source declares.
- Prefer the project's own wrapper (a package script, a make target) over calling the tool directly.
- Quote the source `file:line` for every tool. No source line, no tool.
- When two commands compete for one gate and no source settles it, report both; do not pick.

## Where to look, in order

| # | Source | Where | What it gives |
|---|---|---|---|
| 1 | Declared commands | CLAUDE.md, AGENTS.md, CONTRIBUTING.md, README | The commands the maintainers name for test, lint, typecheck, build, review |
| 2 | CI configs | `.github/workflows/*.yml`, `.gitlab-ci.yml`, `bitbucket-pipelines.yml`, `azure-pipelines.yml`, `.circleci/config.yml`, `Jenkinsfile` | The steps run on pull requests; a step with no local command is CI-only |
| 3 | Task runners | `package.json` scripts and the lockfile's manager, `Makefile`, `justfile`, `Taskfile.yml`, `pyproject.toml` / `tox.ini`, `Cargo.toml`, `go.mod` | The runnable form of each gate |
| 4 | Commit hooks | `.pre-commit-config.yaml`, `.husky/`, `lefthook.yml`, lint-staged config | Checks the project runs before every commit |
| 5 | Static-analysis config | `sonar-project.properties`, `.semgrep.yml`, CodeQL workflows, `.snyk`, `.codeclimate.yml` | Static analysis and security scanners |
| 6 | AI-review config | `.coderabbit.yaml`, docs or CI steps naming an AI reviewer | The project's AI reviewer |
| 7 | MCP tools | The MCP tools present in this session | Reviewers or analysers reachable without a CLI; count one only if a source above names it |
| 8 | Services | `docker-compose.yml` / `compose.yaml`, `Procfile`, README setup | The DB, queue workers or dev server the gates need, and each one's health command |

Lockfile to manager: `package-lock.json` npm, `pnpm-lock.yaml` pnpm, `yarn.lock` yarn, `bun.lock` or `bun.lockb` bun.

## Record per tool

```
name | kind | command | local-capable | auth | result format | source file:line
```

- **kind**: gate (test, lint, typecheck, build), static analysis, AI review, or service.
- **command**: the exact command, as the source declares it.
- **local-capable**: `yes`, or `CI-only` (it runs only after a push, for example a hosted scanner with no local CLI or no local credentials).
- **auth**: the env var name or the login command; `none` if it needs none. Never a value.
- **result format**: exit code, text, JSON or SARIF, PR comments.
- **source**: the `file:line` that names it.

## Examples (never required)

These show the shape of a record; a project counts a tool only through its own files.

- CodeRabbit CLI: `cr review --uncommitted --agent` (or `--committed`, `--base <branch>`), auth `cr auth login`, status `cr doctor`; config `.coderabbit.yaml`.
- SonarQube CLI: `sonar analyze`, `sonar list issues`, auth `sonar auth login`. Most analysis needs a server, so without one it is CI-only.
- Semgrep: `semgrep scan --config <the project's config> --error`; local, no auth for local rules.
