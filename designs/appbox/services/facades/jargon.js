// JargonFacade — one rule for the whole app: every user-facing string and
// metric renders at the reader's level. Levels: plain / balanced / technical
// (default balanced). Copy variants live in the data spine (seed.json sparse
// overrides: textPlain / textBalanced — plain falls back to balanced falls
// back to technical). STATIC view copy lives in the `t` table below.
// Metrics keep raw values in fixtures; scores are computed here.

export const LEVELS = ['plain', 'balanced', 'technical'];

export const level = (prefs = {}) =>
  LEVELS.includes(prefs.jargon) ? prefs.jargon : 'balanced';

// Sparse-override picker: plain → textPlain ?? textBalanced ?? text.
export const pick = (obj, field, lv) => {
  const cap = lv[0].toUpperCase() + lv.slice(1);
  if (lv === 'plain') return obj[`${field}Plain`] ?? obj[`${field}Balanced`] ?? obj[field];
  if (lv === 'balanced') return obj[`${field}Balanced`] ?? obj[field];
  return obj[field];
};

// kimitail: match scores are a display heuristic, not metrology — the
// technical level always shows the raw metric. floor so the pass bar
// (ΔE 2.0 ↔ 95/100) is never rounded up onto itself.
export const scoreDeltaE = (de) => Math.max(0, Math.floor(100 - 2.5 * Number(de)));
export const scoreSsim = (ssim) => Math.round(1000 * Number(ssim)) / 10;
export const PASS_SCORE = 95; // the human-scale pass bar (ΔE ≤ 2.0)

export const band = (score) =>
  score >= 99 ? 'identical to the eye'
  : score >= 95 ? 'near-identical'
  : score >= 91 ? 'slightly different'
  : score >= 85 ? 'noticeably different'
  : 'clearly different';

// Probe chips per level: plain/balanced lead with the /100 score; technical
// shows the raw trio. Each chip carries a title with the raw values.
export const probeChips = (probe, lv) => {
  const de = scoreDeltaE(probe.deltaE);
  const ssim = scoreSsim(probe.ssim);
  if (lv === 'technical') {
    return [
      { text: `SSIM ${probe.ssim}`, title: 'pixel similarity' },
      { text: `${probe.skeleton}`, title: 'skeleton diff' },
      { text: `ΔE ${probe.deltaE}`, title: 'colour distance' },
    ];
  }
  const raw = `SSIM ${probe.ssim} · skeleton ${probe.skeleton} · ΔE ${probe.deltaE}`;
  if (lv === 'balanced') {
    return [
      { text: `${ssim}/100 structure`, title: raw },
      { text: probe.skeleton === 'match' ? 'layout exact' : `layout ${probe.skeleton}`, title: raw },
      { text: `${de}/100 colour`, title: raw },
    ];
  }
  return [
    { text: `${band(de)} · ${de}/100`, title: raw },
    { text: probe.skeleton === 'match' ? 'layout exact' : `layout ${probe.skeleton}`, title: raw },
  ];
};

// Static view copy, keyed by string id, leveled. Rule: if a string carries
// jargon, it lives here with three variants; plain UI labels stay in views.
const COPY = {
  findingsHeadline: {
    technical: 'Coverage held the run — then one fix closed all three',
    balanced: 'Coverage held the run — then one fix closed all three',
    plain: 'The checks stopped the run — then one fix closed all three',
  },
  findingsLede: {
    technical: 'SARIF sidecars, pinned to file:line. The red gate kept these — no terminal scrollback required.',
    balanced: 'Check findings (SARIF), pinned to file:line — the red gate kept these.',
    plain: 'What failed, pinned to the exact file and line — kept here so you never have to read raw build logs.',
  },
  evidenceHeadline: {
    technical: 'All 4 surfaces match their frozen goldens',
    balanced: 'All 4 screens match their goldens',
    plain: 'All 4 screens match the design you approved',
  },
  evidenceLede: {
    technical: 'screen → tests → code, then the probe: SSIM, skeleton diff, colour distance. order.confirmation is on watch.',
    balanced: 'tests, code, then screenshot comparison (SSIM / skeleton / colour match). order.confirmation is on watch.',
    plain: 'Every screen was tested, then compared pixel-by-pixel with the design you approved. order.confirmation is being watched.',
  },
  evidenceEyebrow: {
    technical: 'surface evidence · probe-runner vs frozen golden',
    balanced: 'surface evidence · screenshots vs goldens',
    plain: 'surface evidence · built screens vs approved designs',
  },
  chartNote: {
    technical: 'amber — recovered after a red first attempt. Deploy is queued behind a human gate, so it has no bar.',
    balanced: 'amber — recovered after a failed first attempt. Deploy has no bar: it waits on a human gate.',
    plain: 'Amber means the stage failed once and fixed itself. Shipping has no bar — it waits for your decision.',
  },
  gateFoot: {
    technical: 'An agent can reach this gate. Only a paired human device passes it.',
    balanced: 'An agent can reach this gate. Only a paired human device passes it.',
    plain: 'The agent can bring this decision to you — never take it. Only you, on a paired device, can pass it.',
  },
  railStopOnRed: {
    technical: 'stop-on-red',
    balanced: 'stops on red',
    plain: 'stops at first failure',
  },
  railEsc: {
    technical: 'esc',
    balanced: 'fix attempts',
    plain: 'tries before asking',
  },
  logEyebrow: {
    technical: 'full log',
    balanced: 'full log',
    plain: 'everything that happened',
  },
  // Canvas stage-bar hints — "what to do next" per artifact kind.
  barHintStage: {
    technical: 'Scoped to this stage — ask why, or hold / cancel it here.',
    balanced: 'Ask about this stage, pause it, or cancel it.',
    plain: 'Ask anything about this step — or pause / stop it here.',
  },
  barHintGate: {
    technical: 'The decision happens above — interrogate the evidence before you sign.',
    balanced: 'The decision happens above — ask anything before you sign.',
    plain: 'Your decision is above — ask anything before you decide.',
  },
  barHintFindings: {
    technical: 'Ask why a check failed, or how one fix closed all three.',
    balanced: 'Ask why a check failed, or how one fix closed all three.',
    plain: 'Ask what went wrong, or how one fix closed all three.',
  },
  barHintEvidence: {
    technical: 'Ask what the probe compared, or why one surface is on watch.',
    balanced: 'Ask what was compared, or why one screen is on watch.',
    plain: 'Ask what was compared, or why one screen is being watched.',
  },
  barHintChart: {
    technical: 'Ask where the line spent its time.',
    balanced: 'Ask where the time went.',
    plain: 'Ask where the time went.',
  },
  barHintLog: {
    technical: 'Ask about anything on the line.',
    balanced: 'Ask about anything that happened.',
    plain: 'Ask about anything that happened.',
  },
};

// The leveled static-copy map handed to views as `t`.
export const t = (lv) =>
  Object.fromEntries(Object.entries(COPY).map(([k, v]) => [k, v[lv] ?? v.technical]));
