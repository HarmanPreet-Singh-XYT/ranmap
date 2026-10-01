import type { Metadata } from "next";
import Link from "next/link";
import { Users } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { groupInvitePreview } from "@/lib/data/groups";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { JoinButton } from "./_components/join-button";

export const metadata: Metadata = { title: "Join group" };

export default async function GroupJoinPage({
  params,
  searchParams,
}: {
  params: Promise<{ code: string }>;
  searchParams: Promise<{ requested?: string }>;
}) {
  const { code } = await params;
  const { requested } = await searchParams;
  const supabase = await createClient();
  const preview = await groupInvitePreview(supabase, code);

  if (!preview) {
    return (
      <Card>
        <CardContent className="py-12 text-center">
          <p className="font-medium">Invite not found</p>
          <p className="mt-1 text-sm text-muted-foreground">
            This invite link is invalid or has been rotated.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="mx-auto w-full max-w-md py-8">
      <Card>
        <CardContent className="flex flex-col items-center gap-3 py-8 text-center">
          <span className="flex size-14 items-center justify-center rounded-full bg-emerald-50 text-lg font-bold text-emerald-700">
            {preview.name.slice(0, 1).toUpperCase()}
          </span>
          <p className="font-display text-xl font-bold">{preview.name}</p>
          {preview.description && (
            <p className="text-sm text-muted-foreground">{preview.description}</p>
          )}
          <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <Users className="size-3.5" aria-hidden />
            {preview.member_count} {preview.member_count === 1 ? "member" : "members"}
          </p>

          {requested ? (
            <p className="text-sm text-emerald-700">
              Request sent — an admin will review it.
            </p>
          ) : preview.membership === "member" ? (
            <Button nativeButton={false} render={<Link href={`/app/groups/${preview.group_id}`} />}>
              Open group
            </Button>
          ) : preview.membership === "pending" ? (
            <p className="text-sm text-muted-foreground">Your request is pending.</p>
          ) : (
            <JoinButton code={code} requiresApproval={preview.requires_approval} />
          )}
        </CardContent>
      </Card>
    </div>
  );
}
