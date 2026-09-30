"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Bell,
  Images,
  LayoutDashboard,
  LogOut,
  MapPin,
  MessagesSquare,
  Route,
  Settings,
  UserRoundPlus,
  Users,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { signOut } from "@/app/(account)/actions";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import type { ShellProfile } from "./types";

const NAV = [
  { href: "/app", label: "Home", icon: LayoutDashboard, exact: true },
  { href: "/app/trips", label: "Trips", icon: Route },
  { href: "/app/groups", label: "Groups", icon: Users },
  { href: "/app/friends", label: "Friends", icon: UserRoundPlus },
  { href: "/app/chat", label: "Chat", icon: MessagesSquare },
  { href: "/app/places", label: "Places", icon: MapPin },
  { href: "/app/photos", label: "Photos", icon: Images },
  { href: "/app/notifications", label: "Notifications", icon: Bell },
];

function isActive(pathname: string, href: string, exact = false) {
  return exact ? pathname === href : pathname === href || pathname.startsWith(`${href}/`);
}

/** Desktop navigation rail for the /app area. Hidden below `md`. */
export function AppSidebar({
  profile,
  unreadCount = 0,
}: {
  profile: ShellProfile;
  unreadCount?: number;
}) {
  const pathname = usePathname();

  return (
    <aside className="sticky top-0 hidden h-screen w-64 shrink-0 flex-col border-r border-[#E6E3DA] bg-white/70 md:flex">
      <Link href="/app" className="flex items-center gap-3 px-5 py-5">
        <span className="flex size-9 items-center justify-center rounded-xl border border-emerald-200/60 bg-emerald-50 text-sm font-bold text-emerald-700">
          R
        </span>
        <span className="flex flex-col leading-tight">
          <span className="font-display text-base font-bold tracking-tight text-slate-900">
            Ranmap
          </span>
          <span className="text-[10px] font-bold tracking-wider text-emerald-700 uppercase">
            Plan &amp; Coordinate
          </span>
        </span>
      </Link>

      <nav className="flex flex-1 flex-col gap-1 px-3 py-2">
        {NAV.map(({ href, label, icon: Icon, exact }) => {
          const active = isActive(pathname, href, exact);
          return (
            <Link
              key={href}
              href={href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-semibold transition-colors",
                active
                  ? "bg-emerald-700 text-white"
                  : "text-slate-600 hover:bg-emerald-50 hover:text-emerald-700",
              )}
            >
              <Icon className="size-5" aria-hidden />
              {label}
              {href === "/app/notifications" && unreadCount > 0 && (
                <span
                  className={cn(
                    "ml-auto flex min-w-4 items-center justify-center rounded-full px-1 text-[10px] font-bold",
                    active ? "bg-white text-emerald-700" : "bg-emerald-600 text-white",
                  )}
                >
                  {unreadCount > 9 ? "9+" : unreadCount}
                </span>
              )}
            </Link>
          );
        })}
      </nav>

      <div className="border-t border-[#E6E3DA] p-3">
        <Link
          href="/app/profile"
          className="flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-semibold text-slate-600 transition-colors hover:bg-emerald-50 hover:text-emerald-700"
        >
          <span className="flex size-8 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50">
            <AvatarView seed={profile.avatar_id} />
          </span>
          <span className="min-w-0 flex-1 truncate">
            {profile.display_name || profile.username || "Account"}
          </span>
          <Settings className="size-4 shrink-0 text-slate-400" aria-hidden />
        </Link>
        <form action={signOut}>
          <button
            type="submit"
            className="mt-1 flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-semibold text-slate-600 transition-colors hover:bg-red-50 hover:text-red-700"
          >
            <LogOut className="size-5" aria-hidden />
            Sign out
          </button>
        </form>
      </div>
    </aside>
  );
}
