export const meta = {
  name: 'review-spec-plan',
  description: 'Reviews a spec or plan through four fixed lenses, each on its own seat, filters the merged findings with lead judgment, and returns one verdict.',
  phases: [
    { title: 'Lenses', detail: 'Architect, spec quality, root cause and blast radius, in parallel' },
    { title: 'Filter', detail: 'Lead-judgment verifier: dedupe, bucket every finding, write the report' },
    { title: 'Second opinion', detail: 'Blind opus verifier on dismissed must_fix findings; runs only if there are any' },
  ],
};

// The only copy of the lens -> file -> seat -> model mapping.
const LENSES = [
  { id: 'A', key: 'architect', name: 'architect', file: 'lens-architect.md', agentType: 'senioro:architect', model: 'opus' },
  { id: 'Q', key: 'spec-quality', name: 'spec quality', file: 'lens-spec-quality.md', agentType: 'senioro:investigator', model: 'sonnet' },
  { id: 'R', key: 'root-cause', name: 'root cause', file: 'lens-root-cause.md', agentType: 'senioro:investigator', model: 'opus' },
  { id: 'B', key: 'blast-radius', name: 'blast radius', file: 'lens-blast-radius.md', agentType: 'senioro:investigator', model: 'opus' },
];
const FILTER_SEAT = { agentType: 'senioro:verifier', model: 'sonnet' };
const SECOND_SEAT = { agentType: 'senioro:verifier', model: 'opus' };

// Common lens prompt (one copy; every lens gets it).
const COMMON =
  "Round 2+: the previous report holds the settled findings and their rulings, and the spec's Decisions table holds the decisions. " +
  'Re-raise a settled finding only with new evidence: cite it in `evidence` and set `reraises` to the old id.';

const trim = (p) => String(p).replace(/\/+$/, '');
const target = args.target;
const R = trim(args.R);
const dir = trim(args.dir);
const round = Number(args.round) || 1;
const prior = args.prior || null;
const sha = args.sha || null;
const context = args.context || null;
const reports = `${R}/reports`;
const refs = `${dir}/references`;
const hygiene = `${dir}/../write-spec/references/hygiene.md`;
const report = `${reports}/review-${round}.md`;
const notesPath = (l) => `${reports}/review-${l.key}-${round}.md`;
const priorNotes = (l) => `${prior.replace(/\/[^/]*$/, '')}/review-${l.key}-${round - 1}.md`;

const SEV = ['must_fix', 'should_fix', 'consider'];
const RANK = { must_fix: 0, should_fix: 1, consider: 2 };
const BUCKETS = ['act_on', 'consider', 'noted', 'dismissed'];
const DIMS = ['Conflicts', 'Gaps', 'Mistakes', 'Compactness', 'Completeness', 'Code Hygiene', 'Logic Presentation'];
const str = (max) => ({ type: 'string', minLength: 1, maxLength: max });

// LENS schema (§7.2): at most 12 findings; the spec quality lens also returns the 7 ratings.
const lensSchema = (l) => {
  const finding = {
    type: 'object',
    properties: {
      id: { type: 'string', pattern: `^${l.id}[0-9]+$` },
      lens: { type: 'string', enum: [l.name] },
      severity: { type: 'string', enum: SEV },
      section: str(80),
      claim: str(200),
      evidence: str(200),
      fix: str(200),
      reraises: { type: 'string' },
    },
    required: ['id', 'lens', 'severity', 'section', 'claim', 'evidence', 'fix'],
  };
  const s = { type: 'object', properties: { findings: { type: 'array', maxItems: 12, items: finding } }, required: ['findings'] };
  if (l.id === 'Q') {
    const props = {};
    for (const d of DIMS) props[d] = { type: 'string', enum: ['Ready', 'Revise', 'Rethink'] };
    s.properties.ratings = { type: 'object', properties: props, required: DIMS };
    s.required.push('ratings');
  }
  return s;
};

// FILTER (§7.3): verdict, plus one item per surviving finding with its bucket and why.
const obj = (properties, required) => ({ type: 'object', properties, required });
const FILTER = obj(
  {
    verdict: { type: 'string', enum: ['READY', 'REVISE', 'RETHINK'] },
    items: { type: 'array', items: obj({ id: { type: 'string' }, bucket: { type: 'string', enum: BUCKETS }, why: str(120), merged: { type: 'array', items: { type: 'string' } } }, ['id', 'bucket', 'why']) },
  },
  ['verdict', 'items'],
);
const SECOND = obj(
  { rulings: { type: 'array', items: obj({ id: { type: 'string' }, verdict: { type: 'string', enum: ['CONFIRMED', 'REFUTED'] }, note: str(120) }, ['id', 'verdict', 'note']) } },
  ['rulings'],
);

const WRITE = 'Write it through Bash (a quoted heredoc) if you have no Write tool, creating its directory if needed.';

const lensPrompt = (l) =>
  `GOAL: review ${target} through lens ${l.id} (${l.name}), round ${round}. Read ${refs}/${l.file} and apply it` +
  (l.id === 'Q' ? `, together with the hygiene rules in ${hygiene}.\n` : '.\n') +
  'RULES: read-only on the target and the repo; write only your notes file. Evidence comes only from files you opened or commands you ran in this session: `path:line`, a § quote or a command. ' +
  `${COMMON}\n` +
  (prior ? `PRIOR: previous report ${prior}; your previous notes ${priorNotes(l)}\n` : '') +
  `NOTES FILE: ${notesPath(l)}: your full notes, every finding with its reasoning. ${WRITE}\n` +
  `RETURN per schema: at most 12 findings, most severe first, ids ${l.id}1, ${l.id}2, ...; lens "${l.name}"; ` +
  'severity must_fix (blocks the build), should_fix or consider; claim, evidence and fix ≤ 200 chars each. Zero findings is a valid result.' +
  (l.id === 'Q' ? ' Also return ratings for the seven dimensions.' : '');

// ---------- Lenses ----------
phase('Lenses');
const results = await parallel(
  LENSES.map((l) => () => agent(lensPrompt(l), { label: `lens-${l.key}`, phase: 'Lenses', schema: lensSchema(l), model: l.model, agentType: l.agentType })),
);

const failed = [];
const all = [];
const byId = {};
let ratings = null;
const lenses = LENSES.map((l, i) => {
  const r = results[i];
  if (!r || !Array.isArray(r.findings)) {
    failed.push(l.name);
    return { lens: l.name, failed: true };
  }
  if (l.id === 'Q') ratings = r.ratings || null;
  const c = { must_fix: 0, should_fix: 0, consider: 0 };
  for (const f of r.findings.slice(0, 12)) {
    if (byId[f.id]) continue;
    const g = { ...f, lens: l.name };
    byId[f.id] = g;
    all.push(g);
    c[f.severity] += 1;
  }
  return { lens: l.name, must: c.must_fix, should: c.should_fix, consider: c.consider };
});
log(`Lenses: ${all.length} findings from ${LENSES.length - failed.length}/${LENSES.length} lenses; failed: ${failed.join(', ') || 'none'}`);

if (failed.length === LENSES.length) {
  return { verdict: 'REVISE (incomplete: all lenses)', report: null, lenses, items: [], noted: [], dismissed: [], contested: [] };
}

// ---------- Filter ----------
phase('Filter');
const okNotes = LENSES.filter((l) => !failed.includes(l.name)).map(notesPath);
const filterPrompt =
  `GOAL: act as the lead-judgment filter for review round ${round} of ${target}. Read ${refs}/lead-judgment.md and apply it. ` +
  `Read the target${context ? `, the decisions context ${context}` : ''}${prior ? `, and the previous report ${prior}` : ''}.\n` +
  `LENS NOTES: ${okNotes.join(' ')}\n` +
  `FINDINGS (JSON): ${JSON.stringify(all)}\n` +
  `RATINGS (spec quality lens): ${ratings ? JSON.stringify(ratings) : 'none'}\n` +
  (failed.length ? `FAILED LENSES: ${failed.join(', ')}; say so in the report.\n` : '') +
  'RULES: read-only except the report file. One item per finding id, exactly one bucket each; a finding merged into another gets no item of its own: list its id in the survivor\'s `merged`. why ≤ 120 chars. ' +
  'verdict: RETHINK if any must_fix is act_on; else REVISE if any should_fix is act_on; else READY.\n' +
  `REPORT FILE: ${report}, in lead-judgment.md's format, header Target: ${target} / SHA256: ${sha || 'not given'} / Round: ${round}. ${WRITE}\n` +
  'RETURN per schema: verdict and items.';
const filt = await agent(filterPrompt, { label: 'filter', phase: 'Filter', schema: FILTER, ...FILTER_SEAT });

const bucket = {};
const merged = new Set();
const notes = [];
if (filt && Array.isArray(filt.items)) {
  for (const it of filt.items) {
    if (!byId[it.id] || bucket[it.id]) continue;
    bucket[it.id] = it.bucket;
    for (const m of it.merged || []) if (m !== it.id && byId[m]) merged.add(m);
  }
} else {
  failed.push('filter');
  notes.push('filter failed: every finding is treated as act_on and no report was written');
}
const live = all.filter((f) => !merged.has(f.id));
for (const f of live) {
  if (!bucket[f.id]) {
    bucket[f.id] = 'act_on';
    if (filt) notes.push(`no filter ruling for ${f.id}: kept as act_on`);
  }
}

// ---------- Second opinion ----------
const contested = [];
const dismissedMust = live.filter((f) => bucket[f.id] === 'dismissed' && f.severity === 'must_fix').reverse();
if (dismissedMust.length > 0) {
  phase('Second opinion');
  const roster = dismissedMust.map((f) => ({ id: f.id, section: f.section, claim: f.claim, evidence: f.evidence }));
  const secondPrompt =
    `GOAL: rule on these must_fix findings against ${target}, in this order. Refute by default: read the cited text and code yourself; CONFIRMED only if you reproduce the problem.\n` +
    `FINDINGS (JSON): ${JSON.stringify(roster)}\n` +
    `RULES: read-only except the report file. Rule from the target and the cited evidence only; do not open ${report} before your rulings are final.\n` +
    `REPORT FILE: append (never overwrite) a "### Second opinion" section to ${report}: one line per id with your ruling and note; a CONFIRMED item is contested. ${WRITE}\n` +
    'RETURN per schema: one ruling per id, note ≤ 120 chars.';
  const so = await agent(secondPrompt, { label: 'second-opinion', phase: 'Second opinion', schema: SECOND, ...SECOND_SEAT });
  const rul = {};
  if (so && Array.isArray(so.rulings)) for (const r of so.rulings) rul[r.id] = r.verdict;
  else notes.push('second opinion failed: dismissed must_fix findings are kept as contested');
  for (const f of dismissedMust) {
    if (rul[f.id] === 'REFUTED') continue;
    bucket[f.id] = 'contested';
    contested.push(f.id);
  }
  log(`Second opinion on ${dismissedMust.map((f) => f.id).join(', ')}: contested ${contested.join(', ') || 'none'}`);
}

// ---------- Verdict and return ----------
const hit = (sev, buckets) => live.some((f) => f.severity === sev && buckets.includes(bucket[f.id]));
let verdict = hit('must_fix', ['act_on', 'contested']) ? 'RETHINK' : hit('should_fix', ['act_on']) ? 'REVISE' : 'READY';
if (failed.length) verdict = `${verdict === 'READY' ? 'REVISE' : verdict} (incomplete: ${failed.join(', ')})`;

const cap = (s) => (s.length > 200 ? `${s.slice(0, 199)}…` : s);
const line = (f) => cap(`#${f.id} [${f.severity}] [${f.lens}] ${f.section} — ${f.claim} — ${f.evidence} — ${f.fix}`);
const pick = (b) => live.filter((f) => bucket[f.id] === b).sort((x, y) => RANK[x.severity] - RANK[y.severity]);
const ids = (b) => live.filter((f) => bucket[f.id] === b).map((f) => f.id);
log(`Verdict ${verdict}; act_on ${ids('act_on').length}, consider ${ids('consider').length}, noted ${ids('noted').length}, dismissed ${ids('dismissed').length}`);

const out = {
  verdict,
  report: filt ? report : null,
  lenses,
  items: pick('act_on').concat(pick('consider')).slice(0, 12).map(line),
  noted: ids('noted'),
  dismissed: ids('dismissed'),
  contested,
};
if (notes.length) out.notes = notes.slice(0, 5);
return out;
