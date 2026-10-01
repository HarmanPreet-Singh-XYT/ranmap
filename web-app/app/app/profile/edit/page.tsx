import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { ProfileForm } from "@/app/(account)/_components/profile-form";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export const metadata: Metadata = { title: "Edit profile" };

export default async function EditProfilePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("username, display_name, avatar_id, vehicle_type")
    .eq("id", user.id)
    .single();

  return (
    <div className="mx-auto w-full max-w-3xl space-y-6">
      <Link
        href="/app/profile"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Profile
      </Link>
      <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
        Edit profile
      </h1>
      <Card>
        <CardHeader>
          <CardTitle>Profile</CardTitle>
          <CardDescription>Signed in as {user.email}</CardDescription>
        </CardHeader>
        <CardContent>
          {profile ? (
            <ProfileForm
              userId={user.id}
              username={profile.username}
              displayName={profile.display_name}
              avatarId={profile.avatar_id ?? "default"}
              vehicleType={profile.vehicle_type ?? "car"}
            />
          ) : (
            <p className="text-sm text-muted-foreground">
              Setting up your profile — refresh in a moment, or sign out and back
              in if this persists.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
