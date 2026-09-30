import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { getGroup } from "@/lib/data/groups";
import { loadGroupPhotoGallery } from "@/lib/data/photos";
import { PhotosBrowser } from "@/app/app/photos/photos-browser";

export default async function GroupPhotosPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const group = await getGroup(supabase, id);
  if (!group) notFound();
  const photos = await loadGroupPhotoGallery(supabase, id, user.id);

  return (
    <div className="mx-auto w-full max-w-6xl space-y-4">
      <Link
        href={`/app/groups/${id}`}
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        {group.name}
      </Link>
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Crew photos
        </h1>
        <p className="text-sm text-muted-foreground">
          {photos.length} {photos.length === 1 ? "photo" : "photos"} shared with {group.name}.
        </p>
      </div>
      <PhotosBrowser photos={photos} landmarks={[]} tripTitles={{}} />
    </div>
  );
}
