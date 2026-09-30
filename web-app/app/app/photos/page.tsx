import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { loadPhotoLibrary } from "@/lib/data/photos";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PhotosBrowser } from "./photos-browser";
import { UploadForm } from "./upload-form";

export const metadata: Metadata = { title: "Photos" };

export default async function AppPhotosPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null; // the app layout redirects signed-out visitors

  const result = await loadPhotoLibrary(supabase, user.id);
  if (!result.ok) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Couldn&apos;t load your photos</CardTitle>
          <CardDescription>
            Something went wrong reading your photos. Refresh the page to try
            again.
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  return (
    <div className="mx-auto w-full max-w-6xl space-y-4">
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Photos
        </h1>
        <p className="text-sm text-muted-foreground">
          {result.photos.length === 0
            ? "Pin photos from a place and they'll gather here."
            : `${result.photos.length} ${result.photos.length === 1 ? "photo" : "photos"} across your trips and groups.`}
        </p>
      </div>
      <div className="flex flex-wrap gap-2">
        <Button nativeButton={false} render={<Link href="/app/photos/shared" />} variant="outline" size="sm">
          Shared with me
        </Button>
      </div>
      <UploadForm userId={user.id} />
      <PhotosBrowser
        photos={result.photos}
        landmarks={result.landmarks}
        tripTitles={result.tripTitles}
      />
    </div>
  );
}
