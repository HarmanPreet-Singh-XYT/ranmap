import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { listTripMembers } from "@/lib/data/trips";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { Card, CardContent } from "@/components/ui/card";
import { InviteForm } from "./invite-form";

const STATUS_LABEL = {
  accepted: "Going",
  invited: "Invited",
  declined: "Declined",
} as const;

export default async function TripCrewPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const members = await listTripMembers(supabase, id);

  return (
    <div className="space-y-4">
      <InviteForm tripId={id} />

      {members.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            Just you so far.
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-2">
          {members.map((member) => (
            <li key={member.user_id}>
              <Card size="sm">
                <CardContent className="flex items-center gap-3">
                  <Link
                    href={`/app/people/${member.user_id}`}
                    className="flex min-w-0 flex-1 items-center gap-3 rounded-lg hover:bg-emerald-50/50"
                  >
                    <span className="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50">
                      <AvatarView seed={member.profile?.avatar_id ?? "default"} />
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-medium">
                        {member.profile?.display_name || member.profile?.username || "Member"}
                      </p>
                      <p className="truncate text-xs text-muted-foreground">
                        @{member.profile?.username ?? "unknown"}
                      </p>
                    </div>
                  </Link>
                  <span className="shrink-0 text-xs font-semibold text-slate-500">
                    {STATUS_LABEL[member.invite_status]}
                  </span>
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
