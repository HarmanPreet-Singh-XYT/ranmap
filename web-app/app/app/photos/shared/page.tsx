import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { loadSharedWithMe } from "@/lib/data/photos";
import { PhotosBrowser } from "../photos-browser";

export default async function SharedWithMePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const photos = await loadSharedWithMe(supabase, user.id);

  return (
    <div className="mx-auto w-full max-w-6xl space-y-4">
      <Link
        href="/app/photos"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Photos
      </Link>
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Shared with me
        </h1>
        <p className="text-sm text-muted-foreground">
          {photos.length} {photos.length === 1 ? "photo" : "photos"} from your crew.
        </p>
      </div>
      <PhotosBrowser photos={photos} landmarks={[]} tripTitles={{}} />
    </div>
  );
}
