"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

interface ActiveLinkProps {
  href: string;
  label: string;
  className?: string;
  activeClassName?: string;
  /** Match the path exactly — for index links like `/account` that also prefix
   * siblings (`/account/stats`). */
  exact?: boolean;
  onNavigate?: () => void;
}

/** A nav link that highlights itself when it points at the current route. */
export function ActiveLink({
  href,
  label,
  className = "",
  activeClassName = "",
  exact = false,
  onNavigate,
}: ActiveLinkProps) {
  const pathname = usePathname();
  const active = exact
    ? pathname === href
    : pathname === href || pathname.startsWith(`${href}/`);

  return (
    <Link
      href={href}
      onClick={onNavigate}
      aria-current={active ? "page" : undefined}
      className={`${className} ${active ? activeClassName : ""}`.trim()}
    >
      {label}
    </Link>
  );
}
