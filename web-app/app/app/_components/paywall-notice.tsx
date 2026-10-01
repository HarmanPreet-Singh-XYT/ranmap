import Link from "next/link";
import { ArrowRight, Lock } from "lucide-react";

/**
 * Shows why a write was refused. A free-tier lock gets an Upgrade link; a paid
 * fair-use ceiling just gets the message (there's nothing to upgrade to).
 */
export function PaywallNotice({
  message,
  premium,
}: {
  message: string;
  premium?: boolean;
}) {
  if (!message) return null;

  if (!premium) {
    return (
      <p role="alert" className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
        {message}
      </p>
    );
  }

  return (
    <div
      role="alert"
      className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900"
    >
      <span className="flex items-center gap-2">
        <Lock className="size-4 shrink-0" aria-hidden />
        {message}
      </span>
      <Link
        href="/app/upgrade"
        className="inline-flex items-center gap-1 font-semibold text-emerald-700 hover:text-emerald-800"
      >
        Upgrade
        <ArrowRight className="size-3.5" aria-hidden />
      </Link>
    </div>
  );
}
