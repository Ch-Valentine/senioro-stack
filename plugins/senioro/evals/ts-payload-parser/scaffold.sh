#!/usr/bin/env bash
# Eval fixture (spec 002 U9, case 3): a committed TypeScript repo that already depends on zod and holds one zod schema.
# The prompt asks for src/webhook.ts and a commit; the graders read that file and the git commit call.
set -euo pipefail

git init -q -b main
git config user.name "Eval Fixture"
git config user.email "eval@example.invalid"
git config commit.gpgsign false

mkdir -p src/schemas

cat > package.json <<'EOF'
{
  "name": "billing-hooks",
  "private": true,
  "type": "module",
  "scripts": { "typecheck": "tsc --noEmit", "test": "vitest run" },
  "dependencies": { "zod": "^3.23.8" },
  "devDependencies": { "typescript": "^5.6.0", "vitest": "^2.1.0" }
}
EOF

cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "outDir": "dist"
  },
  "include": ["src"]
}
EOF

cat > README.md <<'EOF'
# billing-hooks

Receives webhooks from the billing provider.
EOF

cat > src/schemas/user.ts <<'EOF'
import { z } from 'zod';

export const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
});

export type User = z.infer<typeof UserSchema>;
EOF

git add -A
git commit -q -m "Add billing-hooks project with a user schema"
