import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, Route, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listRouteTemplates } from "@/lib/data/trips";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PlaceSearch } from "../../_components/place-search";
import { deleteRouteTemplate, saveRouteTemplate } from "../actions";

export const metadata: Metadata = { title: "Saved routes" };

export default async function SavedRoutesPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const routes = await listRouteTemplates(supabase, user.id);

  return (
    <div className="mx-auto w-full max-w-3xl space-y-6">
      <Link
        href="/app/trips"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Trips
      </Link>
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Saved routes
        </h1>
        <p className="text-sm text-muted-foreground">
          Reusable origin → destination templates for planning faster.
        </p>
      </div>

      <Card size="sm">
        <CardContent>
          <form action={saveRouteTemplate} className="space-y-4">
            <input
              name="name"
              required
              maxLength={60}
              placeholder="Route name"
              className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
            />
            <PlaceSearch
              label="From"
              nameField="origin_name"
              latField="origin_lat"
              lngField="origin_lng"
              placeholder="Starting point…"
            />
            <PlaceSearch
              label="To"
              nameField="destination_name"
              latField="destination_lat"
              lngField="destination_lng"
              placeholder="Destination…"
            />
            <Button type="submit" size="sm">
              <Route aria-hidden />
              Save route
            </Button>
          </form>
        </CardContent>
      </Card>

      {routes.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
            <Route className="size-8 text-muted-foreground" aria-hidden />
            <p className="font-medium">No saved routes</p>
            <p className="max-w-sm text-sm text-muted-foreground">
              Save a route you drive often and reuse it when planning.
            </p>
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-2">
          {routes.map((route) => (
            <li key={route.id}>
              <Card size="sm">
                <CardContent className="flex items-center gap-3">
                  <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">
                    <Route className="size-4" aria-hidden />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">{route.name}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {[route.origin_name, route.destination_name].filter(Boolean).join(" → ") ||
                        "No endpoints"}
                    </p>
                  </div>
                  <form action={deleteRouteTemplate}>
                    <input type="hidden" name="id" value={route.id} />
                    <button
                      type="submit"
                      aria-label={`Delete ${route.name}`}
                      className="flex size-7 items-center justify-center rounded-md text-slate-400 hover:bg-red-50 hover:text-red-700"
                    >
                      <Trash2 className="size-4" aria-hidden />
                    </button>
                  </form>
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
