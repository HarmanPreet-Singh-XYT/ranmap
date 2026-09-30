import type { Metadata } from "next";
import { RoutePreview } from "@/app/app/_components/route-preview";

export const metadata: Metadata = { title: "Watch a ride" };

// Near-live: re-fetch the position data at most every 15 seconds.
export const revalidate = 15;

interface WatchData {
  trip: { title: string; status: string; originName: string | null; destinationName: string | null };
  route: [number, number][];
  members: { username: string; lat: number; lng: number; recordedAt: string }[];
  updatedAt: string;
}

async function loadWatch(token: string): Promise<WatchData | null> {
  const serverUrl = process.env.RANMAP_SERVER_URL;
  if (!serverUrl) return null;
  try {
    const res = await fetch(
      `${serverUrl.replace(/\/+$/, "")}/watch/${encodeURIComponent(token)}/data`,
      { next: { revalidate: 15 } },
    );
    if (!res.ok) return null;
    return (await res.json()) as WatchData;
  } catch {
    return null;
  }
}

/**
 * Public, read-only "watch my ride" page. No account required — the token in
 * the URL is the capability. Data comes from the backend's watch endpoint (the
 * capability check happens there); we never expose `RANMAP_SERVER_URL`.
 */
export default async function WatchPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const data = await loadWatch(token);

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-3xl flex-col gap-6 bg-[#FAF8F5] px-5 py-10">
      <header>
        <p className="text-xs font-bold tracking-wide text-emerald-700 uppercase">
          Ranmap · Watch a ride
        </p>
        <h1 className="font-display text-3xl font-bold tracking-tight text-slate-900">
          {data?.trip.title ?? "Ride unavailable"}
        </h1>
        {data?.trip.originName || data?.trip.destinationName ? (
          <p className="text-sm text-muted-foreground">
            {[data.trip.originName, data.trip.destinationName].filter(Boolean).join(" → ")}
          </p>
        ) : null}
      </header>

      {!data ? (
        <p className="rounded-xl bg-white p-6 text-sm text-muted-foreground ring-1 ring-foreground/10">
          This link is invalid or has been turned off by the trip owner.
        </p>
      ) : (
        <>
          <div className="overflow-hidden rounded-xl bg-white ring-1 ring-foreground/10">
            <div className="flex items-center justify-center bg-emerald-50/60 p-6">
              <RoutePreview points={data.route} className="h-56 w-full max-w-lg" />
            </div>
          </div>

          <section className="space-y-2">
            <h2 className="text-sm font-semibold text-slate-700">
              On the road ({data.members.length})
            </h2>
            {data.members.length === 0 ? (
              <p className="text-sm text-muted-foreground">No live positions yet.</p>
            ) : (
              <ul className="space-y-2">
                {data.members.map((member) => (
                  <li
                    key={member.username}
                    className="flex items-center justify-between rounded-xl bg-white px-4 py-3 ring-1 ring-foreground/10"
                  >
                    <span className="font-medium">@{member.username}</span>
                    <span className="text-xs text-muted-foreground">
                      {member.lat.toFixed(3)}, {member.lng.toFixed(3)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <p className="text-xs text-muted-foreground">
            Updated {new Date(data.updatedAt).toLocaleTimeString()} · refreshes
            automatically.
          </p>
        </>
      )}
    </main>
  );
}
