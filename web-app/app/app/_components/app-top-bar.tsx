import Link from "next/link";
import { Bell } from "lucide-react";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import type { ShellProfile } from "./types";

/** Compact header for the /app area on small screens; the sidebar covers `md`+. */
export function AppTopBar({
  profile,
  unreadCount = 0,
}: {
  profile: ShellProfile;
  unreadCount?: number;
}) {
  return (
    <header className="sticky top-0 z-30 flex h-14 items-center justify-between border-b border-[#E6E3DA] bg-[#FAF8F5]/90 px-4 backdrop-blur-md md:hidden">
      <Link href="/app" className="flex items-center gap-2">
        <span className="flex size-8 items-center justify-center rounded-lg border border-emerald-200/60 bg-emerald-50 text-xs font-bold text-emerald-700">
          R
        </span>
        <span className="font-display text-sm font-bold tracking-tight text-slate-900">
          Ranmap
        </span>
      </Link>
      <div className="flex items-center gap-2">
        <Link
          href="/app/notifications"
          aria-label={
            unreadCount > 0 ? `Notifications (${unreadCount} unread)` : "Notifications"
          }
          className="relative flex size-8 items-center justify-center rounded-full text-slate-600 transition-colors hover:bg-emerald-50 hover:text-emerald-700"
        >
          <Bell className="size-5" aria-hidden />
          {unreadCount > 0 && (
            <span className="absolute -top-0.5 -right-0.5 flex min-w-4 items-center justify-center rounded-full bg-emerald-600 px-1 text-[10px] font-bold text-white">
              {unreadCount > 9 ? "9+" : unreadCount}
            </span>
          )}
        </Link>
        <Link
          href="/app/profile"
          aria-label="Profile"
          className="flex size-8 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50 ring-1 ring-[#E6E3DA]"
        >
          <AvatarView seed={profile.avatar_id} />
        </Link>
      </div>
    </header>
  );
}
