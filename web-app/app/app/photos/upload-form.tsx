"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ImagePlus, Loader2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { toEwkt } from "@/lib/data/geo";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PlaceSearch } from "../_components/place-search";

/**
 * Uploads a photo from the browser. Unlike the app, the web can't read the
 * device's live GPS, so the location is picked explicitly. Uploads are stored
 * private and appear in the owner's library.
 */
export function UploadForm({ userId }: { userId: string }) {
  const router = useRouter();
  const [file, setFile] = useState<File | null>(null);
  const [place, setPlace] = useState<{ lat: number; lng: number } | null>(null);
  const [caption, setCaption] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function upload() {
    if (!file || !place || busy) return;
    setBusy(true);
    setError(null);
    try {
      const supabase = createClient();
      const ext =
        (file.name.split(".").pop() ?? "jpg").toLowerCase().replace(/[^a-z0-9]/g, "") ||
        "jpg";
      const path = `${userId}/${Date.now() * 1000}.${ext}`;

      const { error: uploadError } = await supabase.storage
        .from("map-media")
        .upload(path, file, { contentType: file.type || "image/jpeg" });
      if (uploadError) throw uploadError;

      const { error: insertError } = await supabase.from("map_posts").insert({
        user_id: userId,
        point: toEwkt(place.lat, place.lng),
        storage_path: path,
        caption: caption.trim().slice(0, 200) || null,
        visibility: "private",
      });
      if (insertError) throw insertError;

      setFile(null);
      setPlace(null);
      setCaption("");
      router.refresh();
    } catch {
      setError("Couldn't upload that photo. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card size="sm">
      <CardContent className="space-y-4">
        <div className="flex items-center gap-2">
          <ImagePlus className="size-5 text-emerald-700" aria-hidden />
          <span className="text-sm font-semibold text-slate-700">Add a photo</span>
        </div>

        <input
          type="file"
          accept="image/*"
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
          className="block w-full text-sm text-slate-600 file:mr-3 file:rounded-full file:border-0 file:bg-emerald-700 file:px-4 file:py-1.5 file:text-xs file:font-bold file:uppercase file:tracking-wide file:text-white hover:file:bg-emerald-800"
        />

        <PlaceSearch
          label="Where was it taken?"
          nameField="photo_place"
          latField="photo_lat"
          lngField="photo_lng"
          placeholder="Search for the location…"
          onSelect={(selected) =>
            setPlace(selected ? { lat: selected.lat, lng: selected.lng } : null)
          }
        />

        <input
          type="text"
          value={caption}
          onChange={(event) => setCaption(event.target.value)}
          maxLength={200}
          placeholder="Caption (optional)"
          className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
        />

        {error && <p className="text-xs text-red-700">{error}</p>}

        <Button
          type="button"
          size="sm"
          disabled={!file || !place || busy}
          onClick={upload}
        >
          {busy && <Loader2 className="animate-spin" aria-hidden />}
          {busy ? "Uploading…" : "Upload photo"}
        </Button>
      </CardContent>
    </Card>
  );
}
