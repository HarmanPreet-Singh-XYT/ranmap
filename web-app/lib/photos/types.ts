/** A photo the signed-in user can browse, already resolved to a display URL. */
export interface LibraryPhoto {
  id: string;
  tripId: string | null;
  userId: string;
  lat: number;
  lng: number;
  caption: string | null;
  /** ISO timestamp. */
  createdAt: string;
  username: string | null;
  isMine: boolean;
  /** Groups this photo was shared to (searchable). */
  groupNames: string[];
  /** Storage object path, used to derive a file extension for downloads. */
  path: string;
  /** Short-lived signed URL, or null when it couldn't be signed. */
  url: string | null;
}

/** A named place that can label a photo location. */
export interface Landmark {
  name: string;
  lat: number;
  lng: number;
  /** Trip endpoints match within a wider radius than saved places. */
  wide: boolean;
}

/** One location in the library: the photos taken there and what to call it. */
export interface PhotoSpot {
  /** Stable across filtering: the id of the spot's oldest photo. */
  key: string;
  lat: number;
  lng: number;
  title: string;
  /** Oldest first. */
  photos: LibraryPhoto[];
  /** ISO timestamp of the newest photo. */
  latest: string;
}
