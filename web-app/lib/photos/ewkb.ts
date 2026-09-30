/**
 * Decodes a PostGIS `geography(point)` value as PostgREST serializes it: either
 * a GeoJSON object or the hex-encoded EWKB string some server versions return.
 * Returns null for anything it can't decode (never throws), so one odd row
 * can't break a whole page.
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

function pointFromEwkbHex(hex: string): { lat: number; lng: number } | null {
  if (hex.length === 0 || hex.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(hex)) {
    return null;
  }
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  if (bytes.length < 21) return null;

  const view = new DataView(bytes.buffer);
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
