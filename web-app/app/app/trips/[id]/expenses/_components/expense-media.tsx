"use client";

import { useState, type ChangeEvent } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { ImagePlus, Loader2, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { PaywallNotice } from "@/app/app/_components/paywall-notice";
import {
  imageMimeOf,
  IMAGE_TOO_LARGE_MESSAGE,
  isAllowedImage,
  MAX_IMAGE_BYTES,
  UNSUPPORTED_IMAGE_MESSAGE,
} from "@/lib/data/image";
import { attachExpenseMedia, removeExpenseMedia } from "../../../actions";

/**
 * Adds images to an expense that is already logged. Only rendered for the
 * expense's owner — the media table's insert policy allows nobody else, and the
 * cap is measured against their plan.
 */
export function AddExpenseImages({
  expenseId,
  tripId,
  userId,
  limit,
  attached,
}: {
  expenseId: string;
  tripId: string;
  userId: string;
  limit: number;
  attached: number;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{
    message: string;
    premium: boolean;
  } | null>(null);

  const room = limit - attached;

  async function onPick(event: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(event.target.files ?? []);
    event.target.value = "";
    if (files.length === 0) return;

    const accepted = files.slice(0, room);
    setNotice(
      files.length > accepted.length
        ? {
            message: `Only the first ${room} were added — your plan allows ${limit} images per expense.`,
            premium: true,
          }
        : null,
    );

    setBusy(true);
    const paths: string[] = [];
    try {
      const supabase = createClient();
      for (const file of accepted) {
        // Same allow-list the bucket enforces (0054), checked here so the
        // refusal is specific instead of a generic Storage error.
        if (!isAllowedImage(file)) {
          setNotice({ message: UNSUPPORTED_IMAGE_MESSAGE, premium: false });
          continue;
        }
        if (file.size > MAX_IMAGE_BYTES) {
          setNotice({ message: IMAGE_TOO_LARGE_MESSAGE, premium: false });
          continue;
        }
        const ext =
          (file.name.split(".").pop() ?? "jpg")
            .toLowerCase()
            .replace(/[^a-z0-9]/g, "") || "jpg";
        const path = `${userId}/expense-${Date.now()}-${paths.length}.${ext}`;
        const { error } = await supabase.storage
          .from("map-media")
          .upload(path, file, { contentType: imageMimeOf(file) });
        if (error) throw error;
        paths.push(path);
      }
      if (paths.length === 0) return;

      const result = await attachExpenseMedia(expenseId, tripId, paths);
      if (result.error) {
        setNotice({ message: result.error, premium: result.premium ?? false });
        return;
      }
      router.refresh();
    } catch {
      // The rows were never written, so nothing references the uploads: take
      // them back out rather than leaving them orphaned.
      if (paths.length > 0) {
        await createClient().storage.from("map-media").remove(paths);
      }
      setNotice({
        message: "Couldn't attach those images. Please try again.",
        premium: false,
      });
    } finally {
      setBusy(false);
    }
  }

  if (room <= 0) {
    return (
      <Link
        href="/app/upgrade"
        className="text-xs font-semibold text-emerald-700 hover:underline"
      >
        {limit === 1
          ? "One image per expense on the free plan — upgrade"
          : `Your plan allows ${limit} images per expense`}
      </Link>
    );
  }

  return (
    <div className="space-y-1">
      <label className="inline-flex cursor-pointer items-center gap-1 rounded-full border border-[#E6E3DA] bg-white px-2.5 py-1 text-xs font-semibold text-slate-700 transition-colors hover:border-emerald-600 hover:text-emerald-700">
        {busy ? (
          <Loader2 className="size-3.5 animate-spin" aria-hidden />
        ) : (
          <ImagePlus className="size-3.5" aria-hidden />
        )}
        {busy ? "Uploading…" : attached === 0 ? "Add images" : "Add more"}
        <input
          type="file"
          accept="image/*"
          multiple
          className="hidden"
          onChange={onPick}
          disabled={busy}
        />
      </label>
      {notice && (
        <PaywallNotice message={notice.message} premium={notice.premium} />
      )}
    </div>
  );
}

/** Removes one image from an expense. Owner only. */
export function RemoveExpenseImage({
  expenseId,
  tripId,
  storagePath,
}: {
  expenseId: string;
  tripId: string;
  storagePath: string;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  return (
    <button
      type="button"
      aria-label="Remove this image"
      disabled={busy}
      onClick={async () => {
        setBusy(true);
        try {
          await removeExpenseMedia(expenseId, tripId, storagePath);
          router.refresh();
        } finally {
          setBusy(false);
        }
      }}
      className="absolute -right-1.5 -top-1.5 flex size-5 items-center justify-center rounded-full bg-slate-900/60 text-white hover:bg-slate-900"
    >
      {busy ? (
        <Loader2 className="size-3 animate-spin" aria-hidden />
      ) : (
        <X className="size-3" aria-hidden />
      )}
    </button>
  );
}
