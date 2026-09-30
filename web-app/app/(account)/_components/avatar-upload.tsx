"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Camera } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import {
  AVATARS_BUCKET,
  CUSTOM_AVATAR_PREFIX,
  customAvatarPath,
  isCustomAvatar,
} from "@/lib/avatar";
import { Button } from "@/components/ui/button";
import { AvatarView } from "./avatar-view";

const MAX_BYTES = 5 * 1024 * 1024;
// Mirrors kAllowedImageExtensions in lib/core/util/image_upload.dart, minus
// HEIC/HEIF — browsers can't reliably decode those, so they stay mobile-only.
const ALLOWED_TYPES = ["image/png", "image/jpeg", "image/webp", "image/gif"];

function extensionFor(file: File): string {
  const fromName = file.name.split(".").pop()?.toLowerCase();
  if (fromName && /^[a-z0-9]+$/.test(fromName)) return fromName;
  if (file.type === "image/png") return "png";
  if (file.type === "image/webp") return "webp";
  if (file.type === "image/gif") return "gif";
  return "jpg";
}

/**
 * Uploads a profile photo to the `avatars` bucket and writes the
 * `custom:<path>` reference to profiles.avatar_id — the same shape the
 * mobile app's AvatarRepository uses, so the two clients stay in sync.
 * The replaced file is deleted best-effort after the new one is saved.
 */
export function AvatarUpload({
  userId,
  avatarId,
}: {
  userId: string;
  avatarId: string;
}) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const [seed, setSeed] = useState(avatarId);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleFile(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;

    if (!ALLOWED_TYPES.includes(file.type)) {
      setError("Choose a PNG, JPEG, WebP, or GIF image.");
      return;
    }
    if (file.size > MAX_BYTES) {
      setError("Image must be 5 MB or smaller.");
      return;
    }

    setError(null);
    setPending(true);
    const supabase = createClient();
    const path = `${userId}/avatar-${Date.now()}.${extensionFor(file)}`;

    const { error: uploadError } = await supabase.storage
      .from(AVATARS_BUCKET)
      .upload(path, file, { contentType: file.type });
    if (uploadError) {
      setError("Upload failed. Please try again.");
      setPending(false);
      return;
    }

    const nextSeed = `${CUSTOM_AVATAR_PREFIX}${path}`;
    const { error: saveError } = await supabase
      .from("profiles")
      .update({ avatar_id: nextSeed })
      .eq("id", userId);
    if (saveError) {
      await supabase.storage.from(AVATARS_BUCKET).remove([path]);
      setError("Could not save your photo. Please try again.");
      setPending(false);
      return;
    }

    if (isCustomAvatar(seed)) {
      await supabase.storage.from(AVATARS_BUCKET).remove([customAvatarPath(seed)]);
    }

    setSeed(nextSeed);
    setPending(false);
    router.refresh();
  }

  return (
    <div className="flex items-center gap-4">
      <div className="size-16 shrink-0 overflow-hidden rounded-full border border-border bg-muted">
        <AvatarView seed={seed} />
      </div>
      <div>
        <input
          ref={inputRef}
          type="file"
          accept={ALLOWED_TYPES.join(",")}
          className="hidden"
          onChange={handleFile}
        />
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={pending}
          onClick={() => inputRef.current?.click()}
        >
          <Camera />
          {pending ? "Uploading…" : "Change photo"}
        </Button>
        <p className="mt-1.5 text-xs text-muted-foreground">
          PNG, JPEG, WebP or GIF · up to 5 MB.
        </p>
        {error && <p className="mt-1.5 text-xs text-destructive">{error}</p>}
      </div>
    </div>
  );
}
