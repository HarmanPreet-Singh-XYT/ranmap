import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, Wrench } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { saveService } from "./actions";

export const metadata: Metadata = { title: "Vehicle service" };

const FIELD =
  "h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40";

export default async function ServicePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [{ data: service }, { data: stats }] = await Promise.all([
    supabase
      .from("vehicle_service")
      .select("interval_km, last_service_km")
      .eq("user_id", user.id)
      .maybeSingle(),
    supabase.from("trip_stats").select("total_distance_km").eq("user_id", user.id),
  ]);

  const interval = Number(service?.interval_km ?? 10000);
  const lastService = Number(service?.last_service_km ?? 0);
  const odometer = (stats ?? []).reduce(
    (sum, row) => sum + Number((row as { total_distance_km?: number }).total_distance_km ?? 0),
    0,
  );
  const sinceService = Math.max(0, odometer - lastService);
  const dueIn = interval - sinceService;
  const overdue = dueIn <= 0;

  return (
    <div className="mx-auto w-full max-w-3xl space-y-6">
      <Link
        href="/app/profile"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Profile
      </Link>
      <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
        Vehicle service
      </h1>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Wrench className="size-4 text-emerald-700" aria-hidden />
            {overdue ? "Service due" : "Next service"}
          </CardTitle>
          <CardDescription>
            Odometer is estimated from the distance your trips record.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-3 gap-3">
            <div className="rounded-lg bg-muted/50 p-3">
              <p className="font-display text-lg font-extrabold">
                {Math.round(odometer).toLocaleString()}
              </p>
              <p className="text-[11px] font-semibold text-muted-foreground">Odometer (km)</p>
            </div>
            <div className="rounded-lg bg-muted/50 p-3">
              <p className="font-display text-lg font-extrabold">
                {Math.round(sinceService).toLocaleString()}
              </p>
              <p className="text-[11px] font-semibold text-muted-foreground">Since service</p>
            </div>
            <div className={`rounded-lg p-3 ${overdue ? "bg-amber-50" : "bg-muted/50"}`}>
              <p className="font-display text-lg font-extrabold">
                {overdue ? `${Math.abs(Math.round(dueIn)).toLocaleString()} over` : `${Math.round(dueIn).toLocaleString()}`}
              </p>
              <p className="text-[11px] font-semibold text-muted-foreground">
                {overdue ? "Past due" : "Due in (km)"}
              </p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card size="sm">
        <CardContent>
          <form action={saveService} className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <label className="text-xs font-semibold text-slate-700" htmlFor="interval_km">
                  Service interval (km)
                </label>
                <input
                  id="interval_km"
                  name="interval_km"
                  type="number"
                  min="1"
                  max="200000"
                  defaultValue={interval}
                  className={FIELD}
                />
              </div>
              <div className="space-y-1.5">
                <label className="text-xs font-semibold text-slate-700" htmlFor="last_service_km">
                  Odometer at last service (km)
                </label>
                <input
                  id="last_service_km"
                  name="last_service_km"
                  type="number"
                  min="0"
                  defaultValue={lastService}
                  className={FIELD}
                />
              </div>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button type="submit" size="sm">
                Save
              </Button>
            </div>
          </form>
          <form action={saveService} className="mt-3">
            <input type="hidden" name="interval_km" value={interval} />
            <input type="hidden" name="last_service_km" value={Math.round(odometer)} />
            <Button type="submit" variant="outline" size="sm">
              Mark serviced now
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
