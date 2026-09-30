/**
 * Decodes a PostGIS `geometry`/`geography` column value as PostgREST
 * serializes it.
 *
 * PostgREST returns these columns either as a GeoJSON object
 * (`{ "type": "Point", "coordinates": [lng, lat] }`) or — depending on the
 * server version / the request's `Accept` header — as the hex-encoded EWKB
 * string (e.g. `0101000020E6100000…`). This project's server returns the hex
 * form, so reading a point and expecting `.coordinates` silently yields
 * `undefined`. Both shapes are handled here; anything unrecognised yields
 * `null` rather than throwing.
 */
export function pointFromPostgis(
  value: unknown,
): { lat: number; lng: number } | null {
  if (value == null) return null;

  if (typeof value === "string") return pointFromEwkbHex(value);

  if (typeof value === "object") {
    const coords = (value as { coordinates?: unknown }).coordinates;
    if (Array.isArray(coords) && coords.length >= 2) {
      const lng = Number(coords[0]);
      const lat = Number(coords[1]);
      if (Number.isFinite(lat) && Number.isFinite(lng)) return { lat, lng };
    }
  }

  return null;
}

/** Decodes an EWKB Point hex string (`…E6100000<x><y>`; x=lng, y=lat). */
function pointFromEwkbHex(hex: string): { lat: number; lng: number } | null {
  const bytes = decodeHex(hex);
  // Byte order (1) + type (4) + SRID (4) + two float64 (16) = 25 for a point.
  if (!bytes || bytes.length < 21) return null;

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const little = bytes[0] === 1;
  let offset = 1;
  const typeWord = view.getUint32(offset, little);
  offset += 4;
  // Bit 0x20000000 marks an embedded SRID word (PostGIS EWKB).
  if ((typeWord & 0x20000000) !== 0) offset += 4;
  if ((typeWord & 0xff) !== 1) return null; // only Point is handled
  if (offset + 16 > bytes.length) return null;

  const lng = view.getFloat64(offset, little);
  const lat = view.getFloat64(offset + 8, little);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
}

function decodeHex(hex: string): Uint8Array | null {
  if (hex.length === 0 || hex.length % 2 !== 0) return null;
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    const byte = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
    if (Number.isNaN(byte)) return null;
    out[i] = byte;
  }
  return out;
}
