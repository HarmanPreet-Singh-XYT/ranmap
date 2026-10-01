"use client";

import { useState, type ChangeEvent } from "react";
import { useRouter } from "next/navigation";
import { Camera, Loader2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { CUSTOM_AVATAR_PREFIX } from "@/lib/avatar";
import { setGroupAvatar } from "../../actions";

const MAX_BYTES = 5 * 1024 * 1024;

/**
 * Lets a group admin upload a crew photo. The file goes to the public `avatars`
 * bucket under the uploader's own folder (storage RLS requires the `<uid>/`
 * prefix), and the group's avatar_id is set to `custom:<path>` — the same
 * convention the mobile app and AvatarView use.
 */
export function GroupAvatarUpload({ groupId, userId }: { groupId: string; userId: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onChange(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      setError("Choose an image file.");
      return;
    }
    if (file.size > MAX_BYTES) {
      setError("Image must be under 5 MB.");
      return;
    }

    setBusy(true);
    setError(null);
    try {
      const supabase = createClient();
      const ext = (file.name.split(".").pop() ?? "jpg").toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
      const path = `${userId}/group-${groupId}-${Date.now()}.${ext}`;
      const { error: uploadError } = await supabase.storage
        .from("avatars")
        .upload(path, file, { contentType: file.type || "image/jpeg" });
      if (uploadError) throw uploadError;

      await setGroupAvatar(groupId, `${CUSTOM_AVATAR_PREFIX}${path}`);
      router.refresh();
    } catch {
      setError("Couldn't update the group photo. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-1">
      <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-full border border-[#E6E3DA] bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 transition-colors hover:border-emerald-600 hover:text-emerald-700">
        {busy ? <Loader2 className="size-3.5 animate-spin" aria-hidden /> : <Camera className="size-3.5" aria-hidden />}
        {busy ? "Uploading…" : "Change photo"}
        <input
          type="file"
          accept="image/*"
          className="hidden"
          onChange={onChange}
          disabled={busy}
        />
      </label>
      {error && <p className="text-xs text-red-700">{error}</p>}
    </div>
  );
}
