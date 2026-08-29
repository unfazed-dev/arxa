// E2e driver — raises real pending approvals on a live studio engine and
// asserts engine-side state, through the public /api contract (the same
// one the browser uses). Usage:
//   node tool/e2e_driver.mjs <engine-origin> <command> [args]
// Commands:
//   raise <prompt>        create a session + prompt it; prints sessionId.
//                         The agent is instructed to call ask_user_question,
//                         which becomes a pending approval.
//   list                  GET /__arxa/approvals (plugin route).
//   decide <id> <label>   POST a decision (the driver-side 'someone else
//                         answered first' leg).
//   session-events <id>   last raw session events (agent-unblock proof).

const origin = process.argv[2]
const command = process.argv[3]

let seq = 0
async function rpc(method, payload) {
  const res = await fetch(`${origin}/api/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'client-request', rpcId: `drv-${++seq}`, method, payload }),
  })
  if (res.status !== 200) throw new Error(`${method} HTTP ${res.status}: ${await res.text()}`)
  const body = await res.json()
  if (body.result?.ok !== true) throw new Error(`${method} refused: ${JSON.stringify(body.result)}`)
  return body.result.value
}

const instruct = (ask) => `You are a test driver. Call the ask_user_question tool NOW with exactly this question: 'Ship the release?' with options Approve and Deny (mark Approve recommended). ${ask} Do not do anything else; do not answer your own question.`

if (command === 'raise') {
  const extra = process.argv[4] ?? ''
  const created = await rpc('session.create', {})
  console.log('SESSION', created.sessionId)
  await rpc('session.prompt', {
    sessionId: created.sessionId,
    mode: 'queue',
    content: [{ type: 'text', text: instruct(extra) }],
  })
  console.log('PROMPTED')
} else if (command === 'list') {
  const res = await fetch(`${origin}/__arxa/approvals`)
  console.log(res.status, await res.text())
} else if (command === 'decide') {
  const [id, label] = [process.argv[4], process.argv[5] ?? 'Approve']
  const list = await (await fetch(`${origin}/__arxa/approvals`)).json()
  const approval = list.approvals.find((a) => a.id === id) ?? list.approvals[0]
  if (!approval) { console.log('NO-PENDING'); process.exit(2) }
  const answers = approval.questions.map((q) => ({
    id: q.id,
    selected: q.options?.length ? [q.options.find((o) => o.label === label)?.label ?? q.options[0].label] : [],
    custom: undefined,
  }))
  const res = await fetch(`${origin}/__arxa/approvals/action`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'decide', arg: { id: approval.id, answers } }),
  })
  console.log(res.status, await res.text())
} else if (command === 'session-events') {
  const id = process.argv[4]
  const history = await rpc('session.history', { sessionId: id })
  for (const e of history.events.slice(-8)) {
    console.log(e.event.type, JSON.stringify(e.event.data).slice(0, 140))
  }
} else {
  console.error('unknown command', command)
  process.exit(1)
}