"use client";

import { useActionState, useEffect, useState, type ChangeEvent } from "react";
import Link from "next/link";
import { ImagePlus, Loader2, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { PlaceSearch } from "@/app/app/_components/place-search";
import { PaywallNotice } from "@/app/app/_components/paywall-notice";
import {
  imageMimeOf,
  IMAGE_TOO_LARGE_MESSAGE,
  isAllowedImage,
  MAX_IMAGE_BYTES,
  UNSUPPORTED_IMAGE_MESSAGE,
} from "@/lib/data/image";
import { addExpense, type TripActionState } from "../../../actions";

const CATEGORIES = ["fuel", "food", "toll", "lodging", "other"] as const;

const fieldClass =
  "h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40";
const labelClass = "text-xs font-semibold text-slate-700";

const initialState: TripActionState = { error: null };

/** An uploaded image: its storage path, plus a local preview URL for the tile. */
interface Picked {
  path: string;
  preview: string;
}

/**
 * Logs an expense. Location and images are all optional.
 *
 * Images upload to the shared `map-media` bucket as they are picked (the storage
 * policies are folder-scoped, so they have to live under the uploader's own
 * prefix), and only their paths travel with the form. The bucket's read policy
 * makes them visible to everyone on the trip — no separate sharing step.
 *
 * [limit] is the account tier's allowance (free 1, Pro 10, Extreme 25). It is a
 * courtesy check only: the database enforces the real cap, and a refusal comes
 * back from the action as a paywall (`PaywallNotice`).
 */
export function ExpenseForm({
  tripId,
  currency,
  userId,
  limit,
}: {
  tripId: string;
  currency: string;
  userId: string;
  limit: number;
}) {
  const [state, formAction, pending] = useActionState(addExpense, initialState);
  const [picked, setPicked] = useState<Picked[]>([]);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{
    message: string;
    premium: boolean;
  } | null>(null);

  const room = limit - picked.length;

  // A save consumes the staged images, and a refused save has them deleted
  // server-side. Either way the form must stop pointing at them: a stale path
  // would attach a bill that is already attached (or one that no longer exists).
  useEffect(() => {
    if (!state.ok && !state.uploadsDropped) return;
    setPicked((current) => {
      for (const item of current) URL.revokeObjectURL(item.preview);
      return [];
    });
  }, [state]);

  async function onPick(event: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(event.target.files ?? []);
    event.target.value = "";
    if (files.length === 0) return;

    if (room <= 0) {
      setNotice({
        message:
          limit === 1
            ? "Free expenses can carry one image. Upgrade to attach more."
            : `Your plan allows up to ${limit} images per expense.`,
        premium: true,
      });
      return;
    }

    const accepted = files.slice(0, room);
    setNotice(
      files.length > accepted.length
        ? {
            message:
              limit === 1
                ? "Free expenses can carry one image. Upgrade to attach more."
                : `Only the first ${room} images were added — your plan allows ${limit}.`,
            premium: true,
          }
        : null,
    );

    setBusy(true);
    try {
      const supabase = createClient();
      const added: Picked[] = [];
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
        // The timestamp keeps objects distinct; the index keeps a multi-select
        // from colliding within the same millisecond.
        const path = `${userId}/expense-${Date.now()}-${added.length}.${ext}`;
        const { error: uploadError } = await supabase.storage
          .from("map-media")
          .upload(path, file, { contentType: imageMimeOf(file) });
        if (uploadError) throw uploadError;
        added.push({ path, preview: URL.createObjectURL(file) });
      }
      setPicked((current) => [...current, ...added]);
    } catch {
      setNotice({
        message: "Couldn't upload those images. Please try again.",
        premium: false,
      });
    } finally {
      setBusy(false);
    }
  }

  function remove(index: number) {
    setPicked((current) => {
      const next = [...current];
      const [gone] = next.splice(index, 1);
      if (gone) URL.revokeObjectURL(gone.preview);
      return next;
    });
  }

  return (
    <Card size="sm">
      <CardContent>
        <form action={formAction} className="space-y-4">
          <input type="hidden" name="trip_id" value={tripId} />
          <input type="hidden" name="currency" value={currency} />
          {/* One field per image: the action reads them all with getAll. */}
          {picked.map((item) => (
            <input
              key={item.path}
              type="hidden"
              name="attachments"
              value={item.path}
            />
          ))}

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <label className={labelClass} htmlFor="category">
                Category
              </label>
              <select
                id="category"
                name="category"
                defaultValue="fuel"
                className={fieldClass}
              >
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c[0].toUpperCase() + c.slice(1)}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-1.5">
              <label className={labelClass} htmlFor="amount">
                Amount ({currency})
              </label>
              <input
                id="amount"
                name="amount"
                type="number"
                min="0"
                step="0.01"
                required
                className={fieldClass}
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <label className={labelClass} htmlFor="fuel_liters">
                Fuel (L)
              </label>
              <input
                id="fuel_liters"
                name="fuel_liters"
                type="number"
                min="0"
                step="0.1"
                className={fieldClass}
              />
            </div>
            <div className="space-y-1.5">
              <label className={labelClass} htmlFor="note">
                Note
              </label>
              <input id="note" name="note" maxLength={500} className={fieldClass} />
            </div>
          </div>

          <PlaceSearch
            label="Where was it? (optional)"
            nameField="place_name"
            latField="lat"
            lngField="lng"
            placeholder="Search for the place…"
          />

          <div className="space-y-2">
            {/* At the cap, say why there's no control rather than greying one
                out with no explanation. */}
            {room <= 0 ? (
              <Link
                href="/app/upgrade"
                className="text-xs font-semibold text-emerald-700 hover:underline"
              >
                {limit === 1
                  ? "Free expenses carry one image — upgrade to attach more"
                  : `Your plan allows ${limit} images per expense — upgrade for more`}
              </Link>
            ) : (
              <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-full border border-[#E6E3DA] bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 transition-colors hover:border-emerald-600 hover:text-emerald-700">
                {busy ? (
                  <Loader2 className="size-3.5 animate-spin" aria-hidden />
                ) : (
                  <ImagePlus className="size-3.5" aria-hidden />
                )}
                {busy
                  ? "Uploading…"
                  : picked.length === 0
                    ? "Add images"
                    : "Add more images"}
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  className="hidden"
                  onChange={onPick}
                  disabled={busy}
                />
              </label>
            )}

            {picked.length > 0 && (
              <>
                <p className="text-xs text-muted-foreground">
                  {picked.length} of {limit} images · visible to everyone on the
                  trip
                </p>
                <div className="flex flex-wrap gap-2">
                  {picked.map((item, index) => (
                    <div key={item.path} className="relative">
                      {/* Local object URL: the file is uploaded, but a preview
                          shouldn't need a signed round-trip. */}
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={item.preview}
                        alt=""
                        className="size-[72px] rounded-lg border border-[#E6E3DA] object-cover"
                      />
                      <button
                        type="button"
                        aria-label="Remove image"
                        onClick={() => remove(index)}
                        className="absolute -right-1.5 -top-1.5 flex size-5 items-center justify-center rounded-full bg-slate-900/60 text-white hover:bg-slate-900"
                      >
                        <X className="size-3" aria-hidden />
                      </button>
                    </div>
                  ))}
                </div>
              </>
            )}
          </div>

          {notice && (
            <PaywallNotice message={notice.message} premium={notice.premium} />
          )}
          {state.error && (
            <PaywallNotice message={state.error} premium={state.premium} />
          )}

          <Button type="submit" size="sm" disabled={busy || pending}>
            {pending && <Loader2 className="animate-spin" aria-hidden />}
            Add expense
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
