"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Images,
  MessagesSquare,
  Route,
  UserRoundPlus,
  Users,
} from "lucide-react";
import { cn } from "@/lib/utils";

const TABS = [
  { href: "/app/trips", label: "Trips", icon: Route },
  { href: "/app/groups", label: "Groups", icon: Users },
  { href: "/app/friends", label: "Friends", icon: UserRoundPlus },
  { href: "/app/chat", label: "Chat", icon: MessagesSquare },
  { href: "/app/photos", label: "Photos", icon: Images },
];

/** Fixed bottom tab bar for the /app area on small screens. */
export function AppTabBar() {
  const pathname = usePathname();

  return (
    <nav className="fixed inset-x-0 bottom-0 z-40 border-t border-[#E6E3DA] bg-[#FAF8F5]/95 backdrop-blur-md md:hidden">
      <div className="mx-auto flex max-w-7xl items-stretch justify-around">
        {TABS.map(({ href, label, icon: Icon }) => {
          const active = pathname === href || pathname.startsWith(`${href}/`);
          return (
            <Link
              key={href}
              href={href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex flex-1 flex-col items-center gap-1 px-1 py-2 text-[10px] font-semibold transition-colors",
                active ? "text-emerald-700" : "text-slate-500",
              )}
            >
              <Icon className="size-5" aria-hidden />
              {label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
