import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import { listFriends } from "@/lib/data/friends";
import { listMyGroups } from "@/lib/data/groups";
import { listMyTrips } from "@/lib/data/trips";
import { NewChatPicker, type PickerData } from "./picker";

export const metadata: Metadata = { title: "New chat" };

export default async function NewChatPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [friends, groups, trips] = await Promise.all([
    listFriends(supabase, user.id),
    listMyGroups(supabase, user.id),
    listMyTrips(supabase, user.id),
  ]);

  const data: PickerData = {
    friends: friends
      .filter((f) => f.other)
      .map((f) => ({
        id: f.other!.id,
        username: f.other!.username,
        display_name: f.other!.display_name,
        avatar_id: f.other!.avatar_id,
      }))
      .sort((a, b) => a.username.localeCompare(b.username)),
    groups: groups.map((g) => ({ id: g.id, name: g.name, avatar_id: g.avatar_id })),
    // Only trips that are happening or upcoming get a chat worth opening.
    trips: trips
      .filter((t) => t.status === "active" || t.status === "planned")
      .sort((a, b) => (a.status === b.status ? 0 : a.status === "active" ? -1 : 1))
      .map((t) => ({ id: t.id, title: t.title, status: t.status })),
  };

  return <NewChatPicker data={data} />;
}
