import Link from "next/link";
import { Users } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listMyGroups } from "@/lib/data/groups";
import { Card, CardContent } from "@/components/ui/card";

export default async function ChatGroupsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const groups = await listMyGroups(supabase, user.id);

  if (groups.length === 0) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
          <Users className="size-8 text-muted-foreground" aria-hidden />
          <p className="font-medium">No group chats yet</p>
          <p className="max-w-sm text-sm text-muted-foreground">
            Join or create a group from the{" "}
            <Link href="/app/groups" className="font-semibold text-emerald-700">
              Groups
            </Link>{" "}
            page to chat with your crew.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <ul className="space-y-2">
      {groups.map((group) => (
        <li key={group.id}>
          <Link href={`/app/chat/groups/${group.id}`} className="block">
            <Card size="sm" className="transition-colors hover:bg-emerald-50/40">
              <CardContent className="flex items-center gap-3">
                <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-sm font-bold text-emerald-700">
                  {group.name.slice(0, 1).toUpperCase()}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">{group.name}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {group.memberCount} {group.memberCount === 1 ? "member" : "members"}
                  </p>
                </div>
              </CardContent>
            </Card>
          </Link>
        </li>
      ))}
    </ul>
  );
}
