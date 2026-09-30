import type { ReactNode } from "react";
import { ActiveLink } from "@/app/_components/active-link";

const tabs = [
  { href: "/app/chat", label: "Direct", exact: true },
  { href: "/app/chat/groups", label: "Groups" },
  { href: "/app/chat/ai", label: "AI Assistant" },
];

export default function ChatLayout({ children }: { children: ReactNode }) {
  return (
    <div className="space-y-4">
      <nav className="flex gap-2 border-b border-[#E6E3DA] pb-3">
        {tabs.map((tab) => (
          <ActiveLink
            key={tab.href}
            href={tab.href}
            label={tab.label}
            exact={tab.exact}
            className="rounded-full px-4 py-1.5 text-sm font-semibold text-slate-600 transition-colors hover:bg-emerald-50 hover:text-emerald-700"
            activeClassName="bg-emerald-700 text-white hover:bg-emerald-700 hover:text-white"
          />
        ))}
      </nav>
      {children}
    </div>
  );
}
