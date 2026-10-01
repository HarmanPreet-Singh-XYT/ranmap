import type { Metadata } from "next";
import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import { createClient } from "@/lib/supabase/server";
import { unreadNotificationCount } from "@/lib/data/notifications";
import { AppShell } from "./_components/app-shell";
import type { ShellProfile } from "./_components/types";

export const metadata: Metadata = {
  title: { default: "Ranmap", template: "%s · Ranmap" },
};

/**
 * Everything under /app is the signed-in product area and requires a session.
 * This is the single guard for every feature route.
 */
export default async function AppAreaLayout({
  children,
}: {
  children: ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const [{ data: profile }, unreadCount] = await Promise.all([
    supabase
      .from("profiles")
      .select("username, display_name, avatar_id")
      .eq("id", user.id)
      .single(),
    unreadNotificationCount(supabase),
  ]);

  const shellProfile: ShellProfile = {
    username: profile?.username ?? null,
    display_name: profile?.display_name ?? null,
    avatar_id: profile?.avatar_id ?? "default",
  };

  return (
    <AppShell profile={shellProfile} userId={user.id} unreadCount={unreadCount}>
      {children}
    </AppShell>
  );
}
