"use server";

import { redirect } from "next/navigation";
import { createClient } from "../../../lib/supabase/server";

export type ProfileActionState = { error: string | null; saved: boolean };

// Mirrors lib/core/util/validation.dart's kUsername* constants — keep in
// sync if those change.
const USERNAME_MIN = 3;
const USERNAME_MAX = 24;
const USERNAME_PATTERN = /^[a-zA-Z0-9_]+$/;
const DISPLAY_NAME_MAX = 60;
const VEHICLE_TYPES = ["car", "bike", "scooter", "suv", "other"] as const;

function usernameError(value: string): string | null {
  if (value.length < USERNAME_MIN) return `Username must be at least ${USERNAME_MIN} characters`;
  if (value.length > USERNAME_MAX) return `Username must be ${USERNAME_MAX} characters or fewer`;
  if (!USERNAME_PATTERN.test(value)) {
    return "Username can only contain letters, numbers, and underscores";
  }
  return null;
}

export async function updateProfile(
  _prevState: ProfileActionState,
  formData: FormData,
): Promise<ProfileActionState> {
  const username = String(formData.get("username") ?? "").trim();
  const displayName = String(formData.get("display_name") ?? "").trim();
  const vehicleRaw = String(formData.get("vehicle_type") ?? "").trim();
  const vehicleType = (VEHICLE_TYPES as readonly string[]).includes(vehicleRaw)
    ? vehicleRaw
    : "car";

  const usernameErr = usernameError(username);
  if (usernameErr) return { error: usernameErr, saved: false };
  if (displayName.length > DISPLAY_NAME_MAX) {
    return { error: `Display name must be ${DISPLAY_NAME_MAX} characters or fewer`, saved: false };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "You're signed out — refresh and try again.", saved: false };

  const { error } = await supabase
    .from("profiles")
    .update({ username, display_name: displayName || null, vehicle_type: vehicleType })
    .eq("id", user.id);

  if (error) {
    // Postgres unique_violation on the case-insensitive username index.
    if (error.code === "23505") {
      return { error: "That username is already taken.", saved: false };
    }
    return { error: "Could not save your profile. Please try again.", saved: false };
  }

  return { error: null, saved: true };
}

export type DeleteAccountState = { error: string | null };

// Deletion is irreversible and cascades server-side (friendships, trips,
// groups, media, …) — see server/src/routes/account.ts. The web app calls
// that same endpoint rather than duplicating the cascade/cleanup logic.
export async function deleteAccount(
  _prevState: DeleteAccountState,
  formData: FormData,
): Promise<DeleteAccountState> {
  // Enforce the typed confirmation server-side too, so the action can't be
  // invoked directly to delete an account without the explicit step.
  const confirm = String(formData.get("confirm") ?? "");
  if (confirm !== "DELETE") {
    return { error: "Type DELETE to confirm account deletion." };
  }

  const supabase = await createClient();
  // Verify the session (getUser) before trusting it — getSession alone reads an
  // unverified cookie.
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "You're signed out — refresh and try again." };

  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return { error: "You're signed out — refresh and try again." };

  const serverUrl = process.env.RANMAP_SERVER_URL;
  if (!serverUrl) {
    return { error: "Account deletion isn't configured yet. Contact support." };
  }

  let response: Response;
  try {
    response = await fetch(`${serverUrl}/account/delete`, {
      method: "POST",
      headers: { Authorization: `Bearer ${session.access_token}` },
    });
  } catch {
    return { error: "Could not reach the server. Please try again." };
  }

  if (!response.ok) {
    return { error: "Could not delete your account. Please try again." };
  }

  await supabase.auth.signOut();
  redirect("/");
}
