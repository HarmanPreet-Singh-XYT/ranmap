import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { ChangePasswordForm } from "@/app/(account)/_components/change-password-form";
import { DeleteAccount } from "@/app/(account)/_components/delete-account";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export const metadata: Metadata = { title: "Password & security" };

export default async function AccountSecurityPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

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
        Password &amp; security
      </h1>

      <Card>
        <CardHeader>
          <CardTitle>Password</CardTitle>
          <CardDescription>Change the password for your Ranmap account.</CardDescription>
        </CardHeader>
        <CardContent>{user.email && <ChangePasswordForm email={user.email} />}</CardContent>
      </Card>

      <Card className="ring-destructive/20">
        <CardHeader>
          <CardTitle>Danger zone</CardTitle>
          <CardDescription>Deleting your account cannot be undone.</CardDescription>
        </CardHeader>
        <CardContent>
          <DeleteAccount />
        </CardContent>
      </Card>
    </div>
  );
}
