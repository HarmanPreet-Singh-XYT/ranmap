import type { Metadata } from "next";
import { createClient } from "../../../lib/supabase/server";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { ChangePasswordForm } from "../_components/change-password-form";
import { DeleteAccount } from "../_components/delete-account";
import { ProfileForm } from "../_components/profile-form";

export const metadata: Metadata = { title: "Account" };

export default async function AccountPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: profile } = user
    ? await supabase
        .from("profiles")
        .select("username, display_name, avatar_id")
        .eq("id", user.id)
        .single()
    : { data: null };

  return (
    <div className="space-y-8">
      <Card>
        <CardHeader>
          <CardTitle>Profile</CardTitle>
          <CardDescription>Signed in as {user?.email}</CardDescription>
        </CardHeader>
        <CardContent>
          {profile ? (
            <ProfileForm
              userId={user!.id}
              username={profile.username}
              displayName={profile.display_name}
              avatarId={profile.avatar_id ?? "default"}
            />
          ) : (
            <p className="text-sm text-muted-foreground">
              Setting up your profile — refresh in a moment, or sign out and
              back in if this persists.
            </p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Password</CardTitle>
          <CardDescription>
            Change the password for your Ranmap account.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {user?.email && <ChangePasswordForm email={user.email} />}
        </CardContent>
      </Card>

      <Card className="ring-destructive/20">
        <CardHeader>
          <CardTitle>Danger zone</CardTitle>
          <CardDescription>
            Deleting your account cannot be undone.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <DeleteAccount />
        </CardContent>
      </Card>
    </div>
  );
}
