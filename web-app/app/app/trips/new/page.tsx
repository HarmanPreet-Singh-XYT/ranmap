import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import { NewTripForm } from "./new-trip-form";

export const metadata: Metadata = { title: "New trip" };

export default async function NewTripPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data } = user
    ? await supabase
        .from("group_members")
        .select("groups(id, name)")
        .eq("user_id", user.id)
        .eq("status", "active")
    : { data: [] };

  const groups = ((data ?? []) as unknown as { groups: { id: string; name: string } | null }[])
    .map((row) => row.groups)
    .filter((g): g is { id: string; name: string } => Boolean(g));

  return (
    <div className="mx-auto w-full max-w-2xl space-y-6">
      <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
        Plan a trip
      </h1>
      <NewTripForm groups={groups} />
    </div>
  );
}
