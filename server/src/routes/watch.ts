import { Router, type NextFunction, type Request, type Response } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { pointFromPostgis } from "../lib/ewkb.js";
import { decodePolyline } from "../lib/polyline.js";
import { rateLimit } from "../lib/rate-limit.js";
import { supabaseAdmin } from "../lib/supabase.js";

// The public "watch my ride" page. Anyone holding a trip's share token can open
// it — no account — so it serves a self-contained HTML page plus a small JSON
// data endpoint the page polls. The token is the capability: it's validated
// here (service role) and a revoked/unknown token is a plain 404.
export const watchRouter = Router();

// Security headers for a page that can be opened by anyone. The page uses inline
// <style>/<script> and fetches its own data endpoint, so the CSP allows exactly
// those and nothing external; frame-ancestors / X-Frame-Options block
// clickjacking, and nosniff stops MIME confusion.
watchRouter.use((_req: Request, res: Response, next: NextFunction) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader(
    "Content-Security-Policy",
    "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; " +
      "img-src data:; connect-src 'self'; base-uri 'none'; form-action 'none'; " +
      "frame-ancestors 'none'",
  );
  next();
});

watchRouter.use(
  rateLimit({
    name: "watch",
    windowMs: 60 * 1000,
    max: 240,
    message: "Too many requests — please slow down.",
  }),
);

// 32 lowercase hex chars (the trip_shares.token default).
const TOKEN_RE = /^[0-9a-f]{32}$/;
const MAX_MEMBERS = 50;

interface WatchMember {
  username: string;
  lat: number;
  lng: number;
  recordedAt: string;
}

interface WatchData {
  trip: {
    title: string;
    status: string;
    originName: string | null;
    destinationName: string | null;
  };
  /** Route polyline points, raw [lat,lng]. */
  route: [number, number][];
  members: WatchMember[];
  updatedAt: string;
}

async function loadWatch(token: string): Promise<WatchData | null> {
  const { data: share, error: shareError } = await supabaseAdmin
    .from("trip_shares")
    .select("trip_id, revoked_at")
    .eq("token", token)
    .maybeSingle();
  if (shareError) {
    // An infrastructure failure must not be reported as "link not found" — it
    // would hide a real outage as a revoked/unknown share.
    console.error("watch: load share failed:", shareError.message);
    throw new Error("watch: share lookup failed");
  }
  if (!share || share.revoked_at) return null;

  const { data: trip, error: tripError } = await supabaseAdmin
    .from("trips")
    .select("title, status, origin_name, destination_name, route_polyline")
    .eq("id", share.trip_id)
    .maybeSingle();
  if (tripError) {
    console.error("watch: load trip failed:", tripError.message);
    throw new Error("watch: trip lookup failed");
  }
  if (!trip) return null;

  // A finished trip shares no live positions: the link must not keep revealing
  // where riders are after the ride is over.
  const live = trip.status === "active" || trip.status === "planned";

  // Latest ping per accepted member. Querying each member on its own (instead of
  // one recent-N window across everyone) means a quiet rider isn't pushed out by
  // chatty ones.
  const latest = new Map<string, { lat: number; lng: number; recordedAt: string }>();
  if (live) {
    const { data: memberRows, error: membersError } = await supabaseAdmin
      .from("trip_members")
      .select("user_id")
      .eq("trip_id", share.trip_id)
      .eq("invite_status", "accepted")
      .limit(MAX_MEMBERS);
    if (membersError) {
      console.error("watch: load members failed:", membersError.message);
      throw new Error("watch: member lookup failed");
    }
    const results = await Promise.all(
      (memberRows ?? []).map(async (m) => {
        const { data, error } = await supabaseAdmin
          .from("location_pings")
          .select("point, recorded_at")
          .eq("trip_id", share.trip_id)
          .eq("user_id", m.user_id as string)
          .order("recorded_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (error) {
          console.error("watch: load ping failed:", error.message);
          throw new Error("watch: ping lookup failed");
        }
        return { userId: m.user_id as string, ping: data };
      }),
    );
    for (const { userId, ping } of results) {
      if (!ping) continue;
      const loc = pointFromPostgis(ping.point);
      if (!loc) continue;
      latest.set(userId, { ...loc, recordedAt: ping.recorded_at as string });
    }
  }

  const userIds = [...latest.keys()];
  const { data: profiles, error: profilesError } = userIds.length
    ? await supabaseAdmin.from("profiles").select("id, username").in("id", userIds)
    : { data: [] as { id: string; username: string }[], error: null };
  if (profilesError) {
    console.error("watch: load profiles failed:", profilesError.message);
    throw new Error("watch: profile lookup failed");
  }
  const nameById = new Map((profiles ?? []).map((p) => [p.id as string, p.username as string]));

  const members: WatchMember[] = [...latest.entries()].map(([userId, loc]) => ({
    username: nameById.get(userId) ?? "A rider",
    lat: loc.lat,
    lng: loc.lng,
    recordedAt: loc.recordedAt,
  }));

  const route = trip.route_polyline
    ? decodePolyline(trip.route_polyline as string)
    : [];

  return {
    trip: {
      title: trip.title as string,
      status: trip.status as string,
      originName: (trip.origin_name as string | null) ?? null,
      destinationName: (trip.destination_name as string | null) ?? null,
    },
    route,
    members,
    updatedAt: new Date().toISOString(),
  };
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// GET /watch/:token/data -> the JSON the page polls.
watchRouter.get(
  "/:token/data",
  asyncHandler(async (req, res) => {
    const token = String(req.params.token ?? "");
    if (!TOKEN_RE.test(token)) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    const data = await loadWatch(token);
    if (!data) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    res.json(data);
  }),
);

// GET /watch/:token -> the self-contained page.
watchRouter.get(
  "/:token",
  asyncHandler(async (req, res) => {
    const token = String(req.params.token ?? "");
    if (!TOKEN_RE.test(token)) {
      res.status(404).type("html").send(pageShell("Link not found", "not-found"));
      return;
    }
    const data = await loadWatch(token);
    if (!data) {
      res
        .status(404)
        .type("html")
        .send(pageShell("Link not found", "not-found"));
      return;
    }
    res.type("html").send(
      pageShell(`${data.trip.title}`, token, {
        title: data.trip.title,
        route: data.trip.originName && data.trip.destinationName
          ? `${data.trip.originName} → ${data.trip.destinationName}`
          : null,
        status: data.trip.status,
      }),
    );
  }),
);

/**
 * A tiny, dependency-free page. It polls the data endpoint and draws the route
 * and each rider as an SVG — no map SDK, no token, nothing to leak.
 */
function pageShell(
  title: string,
  token: string,
  meta?: { title: string; route: string | null; status: string },
): string {
  const safeTitle = escapeHtml(title);
  const safeRoute = meta?.route ? escapeHtml(meta.route) : "";
  const safeStatus = meta?.status ? escapeHtml(meta.status) : "";
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${safeTitle} · Ranmap</title>
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; font: 16px/1.4 -apple-system, system-ui, Segoe UI, Roboto, sans-serif;
         background: #f3f5f2; color: #14201a; }
  header { padding: 16px 20px; border-bottom: 1px solid #dfe5e0; }
  h1 { margin: 0 0 4px; font-size: 20px; }
  .meta { color: #5c6b62; font-size: 14px; }
  .wrap { max-width: 720px; margin: 0 auto; padding: 16px 20px 40px; }
  .card { background: #fff; border-radius: 16px; padding: 16px; box-shadow: 0 1px 3px rgba(0,0,0,.06); margin-bottom: 16px; }
  svg { display: block; width: 100%; height: auto; }
  ul { list-style: none; margin: 0; padding: 0; }
  li { display: flex; align-items: center; gap: 12px; padding: 10px 0; border-top: 1px solid #eef1ee; }
  li:first-child { border-top: 0; }
  .dot { width: 10px; height: 10px; border-radius: 50%; background: #1f8f4e; flex: 0 0 auto; }
  .who { font-weight: 600; }
  .when { color: #5c6b62; font-size: 13px; margin-left: auto; }
  .empty { color: #5c6b62; }
  .pill { display: inline-block; padding: 2px 10px; border-radius: 999px; background: #e6f2ea; color: #1f8f4e; font-size: 12px; font-weight: 700; }
</style>
</head>
<body>
<header>
  <h1>${safeTitle}</h1>
  <div class="meta">${safeRoute ? `${safeRoute} · ` : ""}<span class="pill" id="status">${safeStatus}</span></div>
</header>
<div class="wrap">
  <div class="card"><svg id="map" viewBox="0 0 1000 640" preserveAspectRatio="xMidYMid meet" aria-label="Route"><path id="route" fill="none" stroke="#1f8f4e" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"/><g id="riders"></g></svg></div>
  <div class="card"><ul id="riders-list"><li class="empty">Loading…</li></ul></div>
  <p class="meta">Updated <span id="updated">—</span> · refreshes every 15s.</p>
</div>
<script>
  const TOKEN = ${JSON.stringify(token)};
  const W = 1000, H = 640, PAD = 40;
  function normalize(points) {
    if (!points.length) return { project: () => null };
    let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
    for (const p of points) { minLat = Math.min(minLat, p[0]); maxLat = Math.max(maxLat, p[0]);
      minLng = Math.min(minLng, p[1]); maxLng = Math.max(maxLng, p[1]); }
    const spanLat = Math.max(maxLat - minLat, 1e-4), spanLng = Math.max(maxLng - minLng, 1e-4);
    const scale = Math.min((W - 2*PAD) / spanLng, (H - 2*PAD) / spanLat);
    const cx = (W - spanLng * scale) / 2, cy = (H - spanLat * scale) / 2;
    return { project: (lat, lng) => [cx + (lng - minLng) * scale, H - (cy + (lat - minLat) * scale)] };
  }
  function render(data) {
    const all = [...data.route, ...data.members.map(m => [m.lat, m.lng])];
    const { project } = normalize(all);
    const routeEl = document.getElementById('route');
    const d = data.route.map((p, i) => { const q = project(p[0], p[1]); return (i ? 'L' : 'M') + q[0].toFixed(1) + ' ' + q[1].toFixed(1); }).join(' ');
    routeEl.setAttribute('d', d);
    const g = document.getElementById('riders');
    g.innerHTML = '';
    const ns = 'http://www.w3.org/2000/svg';
    for (const m of data.members) {
      const q = project(m.lat, m.lng);
      const c = document.createElementNS(ns, 'circle');
      c.setAttribute('cx', q[0].toFixed(1)); c.setAttribute('cy', q[1].toFixed(1));
      c.setAttribute('r', '12'); c.setAttribute('fill', '#1f8f4e'); c.setAttribute('stroke', '#fff'); c.setAttribute('stroke-width', '3');
      g.appendChild(c);
    }
    document.getElementById('status').textContent = data.trip.status;
    const list = document.getElementById('riders-list');
    list.innerHTML = '';
    if (!data.members.length) {
      list.innerHTML = '<li class="empty">No positions shared yet.</li>';
    } else {
      for (const m of data.members) {
        const li = document.createElement('li');
        const dot = document.createElement('span'); dot.className = 'dot';
        const who = document.createElement('span'); who.className = 'who'; who.textContent = '@' + m.username;
        const when = document.createElement('span'); when.className = 'when';
        when.textContent = new Date(m.recordedAt).toLocaleTimeString();
        li.append(dot, who, when); list.appendChild(li);
      }
    }
    document.getElementById('updated').textContent = new Date(data.updatedAt).toLocaleTimeString();
  }
  async function load() {
    try {
      const r = await fetch('/watch/' + TOKEN + '/data', { cache: 'no-store' });
      if (r.ok) render(await r.json());
    } catch (e) { /* transient; retry on the next tick */ }
  }
  load();
  setInterval(load, 15000);
</script>
</body>
</html>`;
}
