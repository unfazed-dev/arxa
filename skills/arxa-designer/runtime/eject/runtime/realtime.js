// @ts-check
// runtime/realtime.js — SSE bus for server-pushed fragment swaps.
//
// Endpoint: GET /__events?channel=<name>
//   Unnamed SSE messages swap through the element's normal hx-target/hx-swap
//   (morph composes). Named events dispatch DOM events. Both are hx-sse v4
//   core behaviours.
//
// Helper (shaped like datastar's ServerSentEventGenerator): one thin typed
// object per request — sse.patch(html), sse.event(name, html).
//
// Event `id:` + a short replay buffer from day one: reconnects are guaranteed
// (deploys, evictions, Vercel's 300s/800s duration wall), and hx-sse resends
// Last-Event-ID automatically.
//
// In-memory bus is the Node default. On Workers there is no isolate affinity
// — events published on isolate A never reach clients on B, silently. Ship the
// convention; the Durable-Object-per-channel adapter is the documented scale
// seam (note: DO hibernation is WebSocket-only; SSE connections keep a DO
// billed — acceptable at the documented seam).

const REPLAY_SIZE = 50;

// channel → array of { id, data, event? }, newest last (ring buffer).
const channels = new Map();

/** @param {string} channel */
function bus(channel) {
  if (!channels.has(channel)) channels.set(channel, []);
  return channels.get(channel);
}

/**
 * @param {string} channel
 * @param {string} data
 * @param {string} [eventName]
 */
function publish(channel, data, eventName) {
  const log = bus(channel);
  const id = String(log.length > 0 ? Number(log[log.length - 1].id) + 1 : 1);
  /** @type {{ id: string, data: string, event?: string }} */
  const entry = { id, data };
  if (eventName) entry.event = eventName;
  log.push(entry);
  if (log.length > REPLAY_SIZE) log.shift();
  return entry;
}

/**
 * Attaches the SSE endpoint to a Hono app.
 * GET /__events?channel=<name> → text/event-stream with replay + keep-alive.
 */
/** @param {import('hono').Hono} app */
export function attachSse(app) {
  app.get('/__events', /** @param {import('./types').Context} context */ (context) => {
    const channel = context.req.query('channel') ?? 'default';
    const enc = new TextEncoder();
    /** @type {ReturnType<typeof setInterval> | undefined} */
    let ping;
    /** @type {ReadableStreamDefaultController | undefined} */
    let myController;
    const stream = new ReadableStream({
      start(controller) {
        myController = controller;
        /** @param {{ id: string, data: string, event?: string }} obj */
        const send = (obj) => controller.enqueue(enc.encode(formatSse(obj)));

        // Replay: send everything after Last-Event-ID (hx-sse sends it on reconnect).
        const log = bus(channel);
        const lastId = Number(context.req.header('Last-Event-ID') ?? 0);
        for (const entry of log) {
          if (Number(entry.id) > lastId) send(entry);
        }

        // Keep-alive every 15s so proxies don't kill idle connections.
        ping = setInterval(() => {
          try { controller.enqueue(enc.encode(': ping\n\n')); } catch { clearInterval(ping); }
        }, 15000);

        // Store the controller so pushToLive() can push.
        const conns = liveConnections.get(channel) ?? new Set();
        conns.add(controller);
        liveConnections.set(channel, conns);
      },
      cancel() {
        clearInterval(ping);
        const conns = liveConnections.get(channel);
        if (conns) conns.delete(myController);
      },
    });
    // Hono/Workers ReadableStream response. (No `connection` header — illegal
    // on HTTP/2 and Workers; the ping interval keeps idle connections alive.)
    return new Response(stream, {
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
      },
    });
  });
}

// channel → Set of ReadableStreamDefaultController
const liveConnections = new Map();

/** @param {{ id: string, data: string, event?: string }} entry */
function formatSse(entry) {
  let out = `id: ${entry.id}\n`;
  if (entry.event) out += `event: ${entry.event}\n`;
  // SSE spec: multi-line payloads need one `data:` line per line, or lines
  // after the first are parsed as bogus field names and silently dropped.
  out += entry.data.split('\n').map((line) => `data: ${line}`).join('\n') + '\n\n';
  return out;
}

/**
 * Publish a patch (unnamed SSE → hx-sse swaps via hx-target/hx-swap).
 * Call from any handler: publishPatch('orders', '<div>Updated</div>')
 * @param {string} channel
 * @param {string} html
 */
export function publishPatch(channel, html) {
  const entry = publish(channel, html);
  pushToLive(channel, entry);
}

/**
 * Publish a named event (dispatches a DOM event on the client).
 * @param {string} channel
 * @param {string} eventName
 * @param {string} [html]
 */
export function publishEvent(channel, eventName, html = '') {
  const entry = publish(channel, html, eventName);
  pushToLive(channel, entry);
}

/** @param {string} channel @param {{ id: string, data: string, event?: string }} entry */
function pushToLive(channel, entry) {
  const conns = liveConnections.get(channel);
  if (!conns) return;
  const buf = new TextEncoder().encode(formatSse(entry));
  for (const controller of conns) {
    try { controller.enqueue(buf); }
    catch { conns.delete(controller); }
  }
}
