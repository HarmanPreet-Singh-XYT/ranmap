import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, ShieldAlert } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listBlocked } from "@/lib/data/settings";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { unblockUser } from "../actions";

export const metadata: Metadata = { title: "Blocked accounts" };

export default async function BlockedAccountsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const blocked = await listBlocked(supabase, user.id);

  return (
    <div className="mx-auto w-full max-w-3xl space-y-6">
      <Link
        href="/app/settings"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Settings
      </Link>
      <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
        Blocked accounts
      </h1>

      {blocked.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
            <ShieldAlert className="size-8 text-muted-foreground" aria-hidden />
            <p className="font-medium">No blocked accounts</p>
            <p className="max-w-sm text-sm text-muted-foreground">
              People you block can&apos;t message you or see your trips.
            </p>
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-2">
          {blocked.map((person) => (
            <li key={person.id}>
              <Card size="sm">
                <CardContent className="flex items-center gap-3">
                  <span className="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50">
                    <AvatarView seed={person.avatar_id ?? "default"} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">
                      {person.display_name || person.username}
                    </p>
                    <p className="truncate text-xs text-muted-foreground">@{person.username}</p>
                  </div>
                  <form action={unblockUser}>
                    <input type="hidden" name="user_id" value={person.id} />
                    <Button type="submit" size="sm" variant="outline">
                      Unblock
                    </Button>
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
