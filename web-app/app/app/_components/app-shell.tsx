import type { ReactNode } from "react";
import { AppSidebar } from "./app-sidebar";
import { AppTabBar } from "./app-tab-bar";
import { LiveRefresh } from "./live-refresh";
import { AppTopBar } from "./app-top-bar";
import type { ShellProfile } from "./types";

/**
 * Chrome for the signed-in product area. Deliberately different from the
 * marketing/account `SiteShell`: a desktop sidebar and a mobile bottom tab bar,
 * no marketing header or footer.
 */
export function AppShell({
  profile,
  userId,
  unreadCount = 0,
  children,
}: {
  profile: ShellProfile;
  userId: string;
  unreadCount?: number;
  children: ReactNode;
}) {
  return (
    <div className="flex min-h-screen w-full bg-[#FAF8F5]">
      <LiveRefresh userId={userId} />
      <AppSidebar profile={profile} unreadCount={unreadCount} />
      <div className="flex min-w-0 flex-1 flex-col">
        <AppTopBar profile={profile} unreadCount={unreadCount} />
        <main className="w-full flex-1 px-4 pt-6 pb-24 sm:px-6 md:px-8 md:pb-10">
          {children}
        </main>
      </div>
      <AppTabBar />
    </div>
  );
}
