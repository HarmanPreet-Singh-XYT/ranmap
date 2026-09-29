const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";

export const AVATARS_BUCKET = "avatars";

/**
 * Mirrors lib/core/constants/avatars.dart on the mobile app: an uploaded
 * photo is stored in profiles.avatar_id as `custom:<storage-path>`, while a
 * bare value is a Multiavatar identicon seed (the column default is
 * 'default'). Keeping the same convention means an avatar set on either
 * client renders on both.
 */
export const CUSTOM_AVATAR_PREFIX = "custom:";

export function isCustomAvatar(seed: string | null | undefined): boolean {
  return typeof seed === "string" && seed.startsWith(CUSTOM_AVATAR_PREFIX);
}

export function customAvatarPath(seed: string): string {
  return seed.slice(CUSTOM_AVATAR_PREFIX.length);
}

/** Public bucket URL — the `avatars` bucket is public, so no signing needed. */
export function customAvatarUrl(seed: string): string {
  return `${SUPABASE_URL}/storage/v1/object/public/${AVATARS_BUCKET}/${customAvatarPath(seed)}`;
}
