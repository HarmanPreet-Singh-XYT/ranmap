"use client";

import {
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Download,
  ExternalLink,
  ImageOff,
  Loader2,
  MapPin,
  Search,
  X,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Modal } from "@/components/ui/modal";
import { buildSpots, downloadName, photoMatches, slug } from "../../../../lib/photos/spots";
import type { Landmark, LibraryPhoto } from "../../../../lib/photos/types";
import { buildZip, chunk } from "../../../../lib/photos/zip";

/**
 * A zip holds at most this many photos, so one archive stays a sensible size to
 * build in a tab. More photos than this download as numbered parts.
 */
const PART_SIZE = 50;
/** Pause between part downloads so browsers treat them as one deliberate batch. */
const PART_GAP_MS = 700;
/** Parallel downloads while building a zip. */
const ZIP_CONCURRENCY = 4;

type Scope = "all" | "mine" | "others";

interface Props {
  photos: LibraryPhoto[];
  landmarks: Landmark[];
  tripTitles: Record<string, string>;
}

interface Viewer {
  /** The photos the viewer pages through (one location's matching photos). */
  list: LibraryPhoto[];
  index: number;
  spotTitle: string;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

function saveBlob(blob: Blob, filename: string) {
  const href = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = href;
  a.download = filename;
  document.body.append(a);
  a.click();
  a.remove();
  // Give the browser a moment to start the download before freeing the URL.
  setTimeout(() => URL.revokeObjectURL(href), 10_000);
}

async function fetchBlob(url: string): Promise<Blob> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download failed (${response.status})`);
  return response.blob();
}

export function PhotosBrowser({ photos, landmarks, tripTitles }: Props) {
  const [query, setQuery] = useState("");
  const [scope, setScope] = useState<Scope>("all");
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [viewer, setViewer] = useState<Viewer | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ text: string; error: boolean } | null>(
    null,
  );

  const mineCount = photos.filter((p) => p.isMine).length;
  const hasOthers = photos.length > mineCount;
  const searching = query.trim().length > 0;

  const spots = useMemo(() => {
    const scoped = photos.filter(
      (p) => scope === "all" || (scope === "mine") === p.isMine,
    );
    return buildSpots(scoped, landmarks);
  }, [photos, landmarks, scope]);

  // While searching, each location shows only its matching photos.
  const visible = useMemo(() => {
    const out: { spot: (typeof spots)[number]; shown: LibraryPhoto[] }[] = [];
    for (const spot of spots) {
      const shown = searching
        ? spot.photos.filter((p) =>
            photoMatches(
              p,
              spot.title,
              p.tripId ? tripTitles[p.tripId] : undefined,
              query,
            ),
          )
        : spot.photos;
      if (shown.length > 0) out.push({ spot, shown });
    }
    return out;
  }, [spots, searching, query, tripTitles]);

  const photoCount = visible.reduce((n, v) => n + v.shown.length, 0);

  const toggle = (key: string) =>
    setExpanded((prev) => {
      const next = new Set(prev);
      if (!next.delete(key)) next.add(key);
      return next;
    });

  const downloadOne = useCallback(
    async (photo: LibraryPhoto, spotTitle: string, index: number) => {
      if (!photo.url) return;
      setBusy(photo.id);
      setNotice(null);
      try {
        saveBlob(
          await fetchBlob(photo.url),
          downloadName(spotTitle, photo, index),
        );
      } catch {
        setNotice({
          text: "Couldn't download that photo. Refresh the page and try again.",
          error: true,
        });
      } finally {
        setBusy(null);
      }
    },
    [],
  );

  /**
   * Downloads [items] as one zip, or — past [PART_SIZE] photos — as numbered
   * parts ("name-part-2-of-3.zip"), building and saving one part at a time so
   * memory stays bounded however large the library is.
   */
  const downloadZips = useCallback(
    async (
      busyKey: string,
      baseName: string,
      items: { photo: LibraryPhoto; name: string }[],
    ) => {
      const targets = items.filter((i) => i.photo.url);
      if (targets.length === 0) return;
      const parts = chunk(targets, PART_SIZE);
      setBusy(busyKey);
      setNotice(null);
      let saved = 0;
      let failed = 0;
      try {
        for (const [p, part] of parts.entries()) {
          setNotice({
            text:
              parts.length > 1
                ? `Preparing part ${p + 1} of ${parts.length}… your browser may ask to allow multiple downloads.`
                : "Preparing your download…",
            error: false,
          });
          const entries: { name: string; data: Uint8Array }[] = [];
          let next = 0;
          const worker = async () => {
            while (next < part.length) {
              const i = next++;
              try {
                const blob = await fetchBlob(part[i].photo.url!);
                entries[i] = {
                  name: part[i].name,
                  data: new Uint8Array(await blob.arrayBuffer()),
                };
              } catch {
                failed++;
              }
            }
          };
          await Promise.all(
            Array.from({ length: Math.min(ZIP_CONCURRENCY, part.length) }, worker),
          );
          const done = entries.filter(Boolean);
          if (done.length === 0) continue;
          saveBlob(
            new Blob([buildZip(done) as BlobPart], { type: "application/zip" }),
            parts.length > 1
              ? `${baseName}-part-${p + 1}-of-${parts.length}.zip`
              : `${baseName}.zip`,
          );
          saved += done.length;
          if (p < parts.length - 1) {
            await new Promise((resolve) => setTimeout(resolve, PART_GAP_MS));
          }
        }
        if (saved === 0) throw new Error("nothing downloaded");
        setNotice({
          text:
            `Downloaded ${saved} ${saved === 1 ? "photo" : "photos"}` +
            (parts.length > 1 ? ` in ${parts.length} zip files` : "") +
            "." +
            (failed ? ` ${failed} couldn't be downloaded — try again for those.` : ""),
          error: failed > 0,
        });
      } catch {
        setNotice({
          text:
            saved > 0
              ? `Stopped after ${saved} photos. Refresh the page and try again for the rest.`
              : "Couldn't build the zip. Refresh the page and try again.",
          error: true,
        });
      } finally {
        setBusy(null);
      }
    },
    [],
  );

  /** One location's photos, named within that location. */
  const downloadSpot = useCallback(
    (spotKey: string, spotTitle: string, list: LibraryPhoto[]) =>
      downloadZips(
        `zip:${spotKey}`,
        slug(spotTitle),
        list.map((photo, i) => ({
          photo,
          name: downloadName(spotTitle, photo, i + 1),
        })),
      ),
    [downloadZips],
  );

  // Arrow keys page through the open viewer (Escape is handled by the modal).
  useEffect(() => {
    if (!viewer) return;
    function onKey(event: KeyboardEvent) {
      if (event.key === "ArrowRight") {
        setViewer((v) =>
          v && v.index < v.list.length - 1 ? { ...v, index: v.index + 1 } : v,
        );
      } else if (event.key === "ArrowLeft") {
        setViewer((v) => (v && v.index > 0 ? { ...v, index: v.index - 1 } : v));
      }
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [viewer]);

  if (photos.length === 0) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
          <ImageOff className="size-8 text-muted-foreground" aria-hidden />
          <p className="font-medium">No photos yet</p>
          <p className="max-w-sm text-sm text-muted-foreground">
            Pin photos from the Ranmap app — hold a spot on the map and choose
            Photo. They show up here, grouped by place, ready to download.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <div className="space-y-3">
        <div className="relative">
          <Search
            className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
            aria-hidden
          />
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search places, captions, trips, people…"
            aria-label="Search photos"
            className="h-10 w-full rounded-full border border-[#E6E3DA] bg-white pl-9 pr-9 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
          />
          {searching && (
            <button
              type="button"
              onClick={() => setQuery("")}
              aria-label="Clear search"
              className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
            >
              <X className="size-4" />
            </button>
          )}
        </div>

        <div className="flex flex-wrap items-center justify-between gap-2">
          {hasOthers && mineCount > 0 ? (
            <div className="flex gap-2" role="group" aria-label="Filter by owner">
              {(
                [
                  ["all", "All"],
                  ["mine", "Mine"],
                  ["others", "From others"],
                ] as const
              ).map(([value, label]) => (
                <button
                  key={value}
                  type="button"
                  aria-pressed={scope === value}
                  onClick={() => setScope(value)}
                  className={`rounded-full px-3 py-1 text-xs font-semibold transition-colors ${
                    scope === value
                      ? "bg-emerald-700 text-white"
                      : "bg-emerald-50 text-emerald-800 hover:bg-emerald-100"
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
          ) : (
            <span />
          )}
          {visible.length > 1 && (
            <Button
              variant="outline"
              size="sm"
              disabled={busy !== null}
              onClick={() =>
                downloadZips(
                  "zip:all",
                  "ranmap-photos",
                  visible.flatMap(({ spot, shown }) =>
                    shown.map((photo, i) => ({
                      photo,
                      // One folder per location inside the zip.
                      name: `${slug(spot.title)}/${downloadName(spot.title, photo, i + 1)}`,
                    })),
                  ),
                )
              }
            >
              {busy === "zip:all" ? (
                <Loader2 className="animate-spin" aria-hidden />
              ) : (
                <Download aria-hidden />
              )}
              {searching || scope !== "all"
                ? `Download these ${photoCount}`
                : `Download everything (${photoCount})`}
            </Button>
          )}
          <p className="text-xs text-muted-foreground" aria-live="polite">
            {searching
              ? `${photoCount} ${photoCount === 1 ? "photo" : "photos"} in ${visible.length} ${visible.length === 1 ? "place" : "places"}`
              : `${photoCount} ${photoCount === 1 ? "photo" : "photos"} · ${visible.length} ${visible.length === 1 ? "place" : "places"}`}
          </p>
        </div>

        {notice && (
          <p
            role={notice.error ? "alert" : "status"}
            className={`rounded-lg px-3 py-2 text-sm ${
              notice.error
                ? "bg-red-50 text-red-700"
                : "bg-emerald-50 text-emerald-800"
            }`}
          >
            {notice.text}
          </p>
        )}
      </div>

      {visible.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            {searching
              ? `Nothing matches “${query.trim()}”.`
              : "No photos in this view."}
          </CardContent>
        </Card>
      ) : (
        visible.map(({ spot, shown }) => {
          // Searching opens every hit so results are visible straight away.
          const open = searching || expanded.has(spot.key);
          const tripNames = [
            ...new Set(
              spot.photos
                .map((p) => (p.tripId ? tripTitles[p.tripId] : undefined))
                .filter((t): t is string => Boolean(t)),
            ),
          ];
          const posters = [
            ...new Set(
              shown.filter((p) => !p.isMine).map((p) => `@${p.username ?? "someone"}`),
            ),
          ];
          const meta = [
            `${shown.length} ${shown.length === 1 ? "photo" : "photos"}`,
            tripNames.length === 1
              ? tripNames[0]
              : tripNames.length > 1
                ? `${tripNames.length} trips`
                : null,
            posters.length > 0
              ? `by ${posters.length <= 2 ? posters.join(", ") : `${posters.length} others`}`
              : null,
            formatDate(spot.latest),
          ]
            .filter(Boolean)
            .join(" · ");
          const zipBusy = busy === `zip:${spot.key}`;
          const downloadable = shown.filter((p) => p.url).length;

          return (
            <Card key={spot.key} size="sm">
              <CardContent className="space-y-3">
                <div className="flex items-center gap-3">
                  <button
                    type="button"
                    onClick={() => toggle(spot.key)}
                    aria-expanded={open}
                    disabled={searching}
                    className="flex min-w-0 flex-1 items-center gap-3 text-left"
                  >
                    <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">
                      <MapPin className="size-5" aria-hidden />
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-medium">
                        {spot.title}
                      </span>
                      <span className="block truncate text-xs text-muted-foreground">
                        {meta}
                      </span>
                    </span>
                    <ChevronDown
                      aria-hidden
                      className={`size-5 shrink-0 text-muted-foreground transition-transform ${
                        open ? "rotate-180" : ""
                      }`}
                    />
                  </button>
                  {downloadable > 0 && (
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={busy !== null}
                      onClick={() => downloadSpot(spot.key, spot.title, shown)}
                      aria-label={`Download photos from ${spot.title}`}
                    >
                      {zipBusy ? (
                        <Loader2 className="animate-spin" aria-hidden />
                      ) : (
                        <Download aria-hidden />
                      )}
                      <span className="hidden sm:inline">
                        {downloadable === 1
                          ? "Download"
                          : `Download all (${downloadable})`}
                      </span>
                    </Button>
                  )}
                </div>

                <ul
                  className={
                    open
                      ? "grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-6"
                      : "flex gap-2 overflow-hidden"
                  }
                >
                  {(open ? shown : shown.slice(0, 8)).map((photo) => (
                    <li
                      key={photo.id}
                      className={open ? "" : "size-14 shrink-0"}
                    >
                      <button
                        type="button"
                        onClick={() =>
                          setViewer({
                            list: shown,
                            index: shown.indexOf(photo),
                            spotTitle: spot.title,
                          })
                        }
                        aria-label={photo.caption ?? `Photo from ${formatDate(photo.createdAt)}`}
                        className="relative block aspect-square w-full overflow-hidden rounded-lg bg-slate-100 outline-none focus-visible:ring-2 focus-visible:ring-emerald-600"
                      >
                        {photo.url ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img
                            src={photo.url}
                            alt=""
                            loading="lazy"
                            className="size-full object-cover"
                          />
                        ) : (
                          <ImageOff
                            className="m-auto size-5 text-muted-foreground"
                            aria-hidden
                          />
                        )}
                        {open && !photo.isMine && photo.username && (
                          <span className="absolute inset-x-0 bottom-0 truncate bg-black/55 px-1 py-0.5 text-[10px] font-semibold text-white">
                            @{photo.username}
                          </span>
                        )}
                      </button>
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>
          );
        })
      )}

      {viewer && (
        <PhotoViewer
          viewer={viewer}
          busy={busy}
          onClose={() => setViewer(null)}
          onStep={(delta) =>
            setViewer((v) =>
              v
                ? {
                    ...v,
                    index: Math.min(v.list.length - 1, Math.max(0, v.index + delta)),
                  }
                : v,
            )
          }
          onDownload={(photo, index) =>
            downloadOne(photo, viewer.spotTitle, index + 1)
          }
        />
      )}
    </div>
  );
}

function PhotoViewer({
  viewer,
  busy,
  onClose,
  onStep,
  onDownload,
}: {
  viewer: Viewer;
  busy: string | null;
  onClose: () => void;
  onStep: (delta: number) => void;
  onDownload: (photo: LibraryPhoto, index: number) => void;
}) {
  const photo = viewer.list[viewer.index];
  const many = viewer.list.length > 1;
  const mapsUrl = `https://www.google.com/maps/search/?api=1&query=${photo.lat},${photo.lng}`;

  return (
    <Modal
      onClose={onClose}
      label={`Photo from ${viewer.spotTitle}`}
      className="flex max-h-[92vh] w-full max-w-4xl flex-col overflow-hidden rounded-2xl bg-white shadow-xl"
    >
      <div className="relative flex min-h-[40vh] flex-1 items-center justify-center bg-slate-950">
        {photo.url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={photo.url}
            alt={photo.caption ?? `Photo from ${viewer.spotTitle}`}
            className="max-h-[68vh] w-full object-contain"
          />
        ) : (
          <div className="flex flex-col items-center gap-2 py-16 text-slate-300">
            <ImageOff className="size-8" aria-hidden />
            <span className="text-sm">This photo couldn&apos;t be loaded.</span>
          </div>
        )}
        {many && viewer.index > 0 && (
          <button
            type="button"
            onClick={() => onStep(-1)}
            aria-label="Previous photo"
            className="absolute left-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-2 text-white hover:bg-black/70"
          >
            <ChevronLeft className="size-5" />
          </button>
        )}
        {many && viewer.index < viewer.list.length - 1 && (
          <button
            type="button"
            onClick={() => onStep(1)}
            aria-label="Next photo"
            className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-2 text-white hover:bg-black/70"
          >
            <ChevronRight className="size-5" />
          </button>
        )}
        {many && (
          <span className="absolute left-3 top-3 rounded-full bg-black/55 px-2.5 py-1 text-xs font-semibold text-white">
            {viewer.index + 1} / {viewer.list.length}
          </span>
        )}
        <button
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="absolute right-3 top-3 rounded-full bg-black/55 p-1.5 text-white hover:bg-black/75"
        >
          <X className="size-4" />
        </button>
      </div>

      <div className="flex flex-wrap items-center gap-3 p-4">
        <div className="min-w-0 flex-1">
          <p className="truncate font-medium">{viewer.spotTitle}</p>
          <p className="truncate text-xs text-muted-foreground">
            {photo.isMine ? "You" : `@${photo.username ?? "someone"}`} ·{" "}
            {formatDate(photo.createdAt)}
          </p>
          {photo.caption && (
            <p className="mt-1 text-sm text-slate-700">{photo.caption}</p>
          )}
        </div>
        <Button
          variant="outline"
          nativeButton={false}
          render={<a href={mapsUrl} target="_blank" rel="noreferrer" />}
        >
          <ExternalLink aria-hidden />
          Map
        </Button>
        <Button
          disabled={!photo.url || busy === photo.id}
          onClick={() => onDownload(photo, viewer.index)}
        >
          {busy === photo.id ? (
            <Loader2 className="animate-spin" aria-hidden />
          ) : (
            <Download aria-hidden />
          )}
          Download
        </Button>
      </div>
    </Modal>
  );
}
