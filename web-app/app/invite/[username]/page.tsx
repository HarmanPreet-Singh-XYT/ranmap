import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { UserPlus } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { sendFriendRequest } from "@/app/app/friends/actions";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { SiteShell } from "../../_components/site-shell";

export const metadata: Metadata = { title: "Invitation" };

/**
 * A personal invite link (`/invite/<username>`). Signed-out visitors are sent
 * to sign in and returned here; signed-in visitors can send a friend request.
 * Mirrors the app's invite_landing_screen.
 */
export default async function InvitePage({
  params,
}: {
  params: Promise<{ username: string }>;
}) {
  const { username } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect(`/login?next=${encodeURIComponent(`/invite/${username}`)}`);
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, username, display_name, avatar_id")
    .ilike("username", username)
    .maybeSingle();

  return (
    <SiteShell>
      <main className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center px-5 py-16">
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-8 text-center">
            {!profile ? (
              <>
                <p className="font-display text-xl font-bold">Invite not found</p>
                <p className="text-sm text-muted-foreground">
                  No one goes by @{username}.
                </p>
                <Button nativeButton={false} render={<Link href="/app/friends" />} variant="outline">
                  Find people
                </Button>
              </>
            ) : profile.id === user.id ? (
              <>
                <p className="font-display text-xl font-bold">That&apos;s you</p>
                <Button nativeButton={false} render={<Link href="/app/friends" />} variant="outline">
                  Go to Friends
                </Button>
              </>
            ) : (
              <>
                <span className="flex size-16 items-center justify-center overflow-hidden rounded-full bg-emerald-50 ring-1 ring-[#E6E3DA]">
                  <AvatarView seed={profile.avatar_id ?? "default"} />
                </span>
                <p className="font-display text-xl font-bold">
                  {profile.display_name || profile.username}
                </p>
                <p className="-mt-2 text-sm text-muted-foreground">@{profile.username}</p>
                <p className="max-w-xs text-sm text-muted-foreground">
                  invited you to connect on Ranmap.
                </p>
                <form action={sendFriendRequest}>
                  <input type="hidden" name="user_id" value={profile.id} />
                  <Button type="submit">
                    <UserPlus aria-hidden />
                    Add friend
                  </Button>
                </form>
              </>
            )}
          </CardContent>
        </Card>
      </main>
    </SiteShell>
  );
}
