import type { Metadata } from "next";
import Link from "next/link";
import { Bell, KeyRound, LogOut, ShieldAlert, UserRound } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { getNotificationPrefs } from "@/lib/data/settings";
import { signOut } from "@/app/(account)/actions";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { updateNotificationPrefs } from "./actions";

export const metadata: Metadata = { title: "Settings" };

const TOGGLES = [
  { key: "trip_invites", label: "Trip invitations" },
  { key: "chat_messages", label: "Chat messages" },
  { key: "trip_updates", label: "Trip updates" },
] as const;

const LINKS = [
  { href: "/app/settings/blocked", label: "Blocked accounts", description: "People you've blocked", icon: ShieldAlert },
  { href: "/app/settings/socials", label: "Linked socials & phone", description: "Handles and verified number", icon: UserRound },
  { href: "/app/settings/account", label: "Password & security", description: "Password and account deletion", icon: KeyRound },
];

export default async function SettingsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const prefs = await getNotificationPrefs(supabase, user.id);

  return (
    <div className="mx-auto w-full max-w-3xl space-y-6">
      <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
        Settings
      </h1>

      <Card>
        <CardHeader>
          <CardTitle>Notifications</CardTitle>
          <CardDescription>
            Choose which push notifications you receive. Everything is on by
            default.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form action={updateNotificationPrefs} className="space-y-4">
            {TOGGLES.map((toggle) => (
              <label
                key={toggle.key}
                className="flex items-center justify-between gap-4 text-sm font-medium text-slate-700"
              >
                {toggle.label}
                <input
                  type="checkbox"
                  name={toggle.key}
                  value="1"
                  defaultChecked={prefs[toggle.key]}
                  className="size-4 accent-emerald-700"
                />
              </label>
            ))}
            <Button type="submit" size="sm">
              <Bell aria-hidden />
              Save preferences
            </Button>
          </form>
        </CardContent>
      </Card>

      <div className="grid gap-2 sm:grid-cols-3">
        {LINKS.map(({ href, label, description, icon: Icon }) => (
          <Link
            key={href}
            href={href}
            className="flex items-start gap-3 rounded-xl bg-white p-4 ring-1 ring-foreground/10 transition-colors hover:bg-emerald-50/40"
          >
            <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-emerald-50 text-emerald-700">
              <Icon className="size-5" aria-hidden />
            </span>
            <span className="min-w-0">
              <span className="block font-medium text-slate-900">{label}</span>
              <span className="block text-xs text-muted-foreground">{description}</span>
            </span>
          </Link>
        ))}
      </div>

      <form action={signOut}>
        <Button type="submit" variant="ghost" size="sm">
          <LogOut aria-hidden />
          Sign out
        </Button>
      </form>
    </div>
  );
}
