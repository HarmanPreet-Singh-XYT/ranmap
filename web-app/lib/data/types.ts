/** Domain row types mirroring the Supabase schema the mobile app uses. */

export interface PublicProfile {
  id: string;
  username: string;
  display_name: string | null;
  avatar_id: string | null;
  vehicle_type?: string | null;
}

export type TripStatus = "planned" | "active" | "completed" | "cancelled";

export interface Trip {
  id: string;
  group_id: string | null;
  created_by: string;
  title: string;
  status: TripStatus;
  origin_name: string | null;
  destination_name: string | null;
  scheduled_start: string | null;
  started_at: string | null;
  ended_at: string | null;
  route_polyline: string | null;
  currency: string;
  created_at: string;
}

export type InviteStatus = "invited" | "accepted" | "declined";

export interface TripMember {
  trip_id: string;
  user_id: string;
  invite_status: InviteStatus;
  joined_at: string | null;
  profile: PublicProfile | null;
}

export type StopKind = "food" | "scenery" | "fuel" | "rest" | "custom";

export interface TripStop {
  id: string;
  trip_id: string;
  created_by: string;
  kind: StopKind;
  name: string;
  notes: string | null;
  sort_order: number;
  planned_arrival: string | null;
  point: { lat: number; lng: number } | null;
}

export type ExpenseCategory = "fuel" | "food" | "toll" | "lodging" | "other";

export interface TripExpense {
  id: string;
  trip_id: string;
  user_id: string;
  category: ExpenseCategory;
  amount: number;
  currency: string;
  fuel_liters: number | null;
  odometer_km: number | null;
  note: string | null;
  logged_at: string | null;
}

export interface TripChecklistItem {
  id: string;
  trip_id: string;
  created_by: string;
  label: string;
  done: boolean;
  sort_order: number;
}

export interface TripInvite {
  trip_id: string;
  invite_status: InviteStatus;
  trips: Partial<Trip> | null;
}

export type GroupRole = "owner" | "admin" | "member";
export type MemberStatus = "pending" | "active";

export interface Group {
  id: string;
  name: string;
  owner_id: string;
  description: string | null;
  avatar_id: string | null;
  invite_code: string | null;
  invite_requires_approval: boolean;
  created_at: string;
}

export interface GroupMember {
  group_id: string;
  user_id: string;
  role: GroupRole;
  status: MemberStatus;
  joined_at: string | null;
  profile: PublicProfile | null;
}

export interface GroupSummary extends Group {
  role: GroupRole;
  memberCount: number;
}

export interface GroupPreview {
  group_id: string;
  name: string;
  description: string | null;
  avatar_id: string | null;
  member_count: number;
  requires_approval: boolean;
  membership: "member" | "pending" | "none";
}

export type FriendshipStatus = "pending" | "accepted" | "blocked";

export interface Friendship {
  id: string;
  requester_id: string;
  addressee_id: string;
  status: FriendshipStatus;
  created_at: string;
  other: PublicProfile | null;
}

export type MessageKind = "text" | "photo" | "location" | "trip";

export interface ChatMessage {
  id: string;
  trip_id: string | null;
  group_id: string | null;
  conversation_id: string | null;
  sender_id: string;
  body: string | null;
  kind: MessageKind;
  payload: Record<string, unknown> | null;
  created_at: string;
  sender: PublicProfile | null;
}

export interface AppNotification {
  id: string;
  kind: string;
  title: string;
  body: string | null;
  data: Record<string, unknown>;
  read_at: string | null;
  created_at: string;
}

export interface AiConversation {
  id: string;
  title: string | null;
  created_at: string;
}

export interface AiMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  created_at: string;
}

export interface DirectConversation {
  conversation_id: string;
  other_id: string;
  username: string;
  display_name: string | null;
  avatar_id: string | null;
  last_body: string | null;
  last_kind: string | null;
  last_sender: string | null;
  last_at: string | null;
}
