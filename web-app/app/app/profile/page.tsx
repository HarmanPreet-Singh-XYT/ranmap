import type { Metadata } from "next";
import Link from "next/link";
import {
  Bell,
  Car,
  CreditCard,
  FileText,
  LogOut,
  Settings,
  Sparkles,
  TrendingUp,
  UserRound,
  Wrench,
} from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { getPlanUsage } from "@/lib/data/usage";
import { signOut } from "@/app/(account)/actions";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

export const metadata: Metadata = { title: "Profile" };

const VEHICLE_LABELS: Record<string, string> = {
  car: "Car",
  bike: "Bike",
  scooter: "Scooter",
  suv: "SUV",
  other: "Other",
};

function formatNumber(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${Math.round(n / 1_000)}k`;
  return String(n);
}

const LINKS = [
  { href: "/app/settings", label: "Settings", description: "Notifications, blocked accounts, linked socials", icon: Settings },
  { href: "/app/profile/edit", label: "Edit profile", description: "Name, username, avatar, vehicle", icon: UserRound },
  { href: "/app/documents", label: "Documents", description: "Private license, insurance, and ticket wallet", icon: FileText },
  { href: "/app/service", label: "Vehicle service", description: "Service interval and odometer reminders", icon: Wrench },
  { href: "/app/profile/billing", label: "Billing", description: "Plan, payment, and subscription", icon: CreditCard },
  { href: "/app/profile/stats", label: "Your stats", description: "Trips, distance, and groups", icon: TrendingUp },
  { href: "/app/notifications", label: "Notifications", description: "Invites, messages, and alerts", icon: Bell },
];

export default async function ProfilePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [{ data: profile }, { data: planRow }, usage] = await Promise.all([
    supabase
      .from("profiles")
      .select("username, display_name, avatar_id, vehicle_type")
      .eq("id", user.id)
      .single(),
    supabase.rpc("my_plan").maybeSingle(),
    getPlanUsage(),
  ]);

  const plan = (planRow ?? {}) as { is_pro?: boolean; is_extreme?: boolean; plan_expires_at?: string | null };
  const isPro = plan.is_pro ?? false;
  const isExtreme = plan.is_extreme ?? false;
  const planName = isExtreme ? "Ranmap Extreme" : isPro ? "Ranmap Pro" : "Explorer (Free)";
  const vehicle = profile?.vehicle_type ? VEHICLE_LABELS[profile.vehicle_type] ?? profile.vehicle_type : null;

  return (
    <div className="mx-auto w-full max-w-4xl space-y-6">
      <div className="flex flex-col items-center gap-4 rounded-xl bg-white p-6 ring-1 ring-foreground/10 sm:flex-row sm:items-center">
        <span className="flex size-20 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50 ring-1 ring-[#E6E3DA]">
          <AvatarView seed={profile?.avatar_id ?? "default"} />
        </span>
        <div className="min-w-0 flex-1 text-center sm:text-left">
          <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
            {profile?.display_name || profile?.username || "You"}
          </h1>
          <p className="text-sm text-muted-foreground">@{profile?.username ?? "unknown"}</p>
          {vehicle && (
            <span className="mt-2 inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-800">
              <Car className="size-3.5" aria-hidden />
              {vehicle}
            </span>
          )}
        </div>
        <Button nativeButton={false} render={<Link href="/app/profile/edit" />} variant="outline" size="sm">
          Edit profile
        </Button>
      </div>

      <Card>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs font-semibold text-muted-foreground">Current plan</p>
              <p className="font-display text-xl font-bold text-slate-900">{planName}</p>
            </div>
            <Badge variant={isPro ? "default" : "secondary"}>{isPro ? "Active" : "Free"}</Badge>
          </div>

          {usage && usage.usage.length > 0 && (
            <div className="space-y-3 border-t border-[#E6E3DA] pt-4">
              {usage.usage.map((meter) => {
                const pct = Math.min(100, Math.round((meter.used / meter.limit) * 100));
                return (
                  <div key={meter.feature} className="space-y-1.5">
                    <div className="flex items-center justify-between text-xs font-semibold text-slate-600">
                      <span>{meter.label}</span>
                      <span>
                        {formatNumber(meter.used)} / {formatNumber(meter.limit)} {meter.unit}
                      </span>
                    </div>
                    <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
                      <div
                        className={`h-full rounded-full ${pct >= 90 ? "bg-amber-500" : "bg-emerald-600"}`}
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {!isPro && (
            <Button nativeButton={false} render={<Link href="/app/upgrade" />} className="w-full" size="lg">
              <Sparkles aria-hidden />
              Upgrade your plan
            </Button>
          )}
        </CardContent>
      </Card>

      <div className="grid gap-2 sm:grid-cols-2">
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
