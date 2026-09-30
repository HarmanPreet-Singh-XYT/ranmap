import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, BadgeCheck, Phone } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { getPrivateProfile } from "@/lib/data/settings";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { updateSocials } from "../actions";
import { PhoneVerify } from "./phone-verify";

export const metadata: Metadata = { title: "Linked socials & phone" };

const FIELD =
  "h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40";

const SOCIALS = [
  { key: "instagram", label: "Instagram", placeholder: "@handle" },
  { key: "x", label: "X", placeholder: "@handle" },
  { key: "tiktok", label: "TikTok", placeholder: "@handle" },
  { key: "website", label: "Website", placeholder: "https://…" },
] as const;

export default async function SocialsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const profile = await getPrivateProfile(supabase);

  return (
    <div className="mx-auto w-full max-w-3xl space-y-6">
      <Link
        href="/app/settings"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Settings
      </Link>
      <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
        Linked socials &amp; phone
      </h1>

      <Card>
        <CardHeader>
          <CardTitle>Phone</CardTitle>
          <CardDescription>
            {profile.phone_verified
              ? "Your number is verified."
              : "Verify a number to receive SMS convoy alerts and SOS."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {profile.phone_verified && profile.phone_number ? (
            <p className="flex items-center gap-2 text-sm font-medium text-emerald-800">
              <BadgeCheck className="size-4" aria-hidden />
              {profile.phone_number}
            </p>
          ) : (
            <PhoneVerify />
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Phone className="size-4 text-emerald-700" aria-hidden />
            Socials
          </CardTitle>
          <CardDescription>Shown to friends on your profile.</CardDescription>
        </CardHeader>
        <CardContent>
          <form action={updateSocials} className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              {SOCIALS.map((social) => (
                <div key={social.key} className="space-y-1.5">
                  <label className="text-xs font-semibold text-slate-700" htmlFor={social.key}>
                    {social.label}
                  </label>
                  <input
                    id={social.key}
                    name={social.key}
                    defaultValue={profile.socials[social.key] ?? ""}
                    placeholder={social.placeholder}
                    maxLength={200}
                    className={FIELD}
                  />
                </div>
              ))}
            </div>
            <Button type="submit" size="sm">
              Save socials
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
