import { pointFromPostgis } from "@/lib/photos/ewkb";

export { pointFromPostgis };

/** A decoded PostGIS point. */
export interface LatLng {
  lat: number;
  lng: number;
}

export function latLngFromPostgis(value: unknown): LatLng | null {
  return pointFromPostgis(value);
}

/**
 * Encodes a point the way the mobile app writes PostGIS columns
 * (`LatLngPoint.toEwkt()`), so web-created rows read back identically.
 */
export function toEwkt(lat: number, lng: number): string {
  return `SRID=4326;POINT(${lng} ${lat})`;
}

/**
 * Decodes a Google/Mapbox encoded polyline (precision 5) into [lat, lng]
 * pairs — used to draw route previews from `trips.route_polyline`.
 */
export function decodePolyline(encoded: string | null | undefined): [number, number][] {
  if (!encoded) return [];
  const factor = 1e5;
  const points: [number, number][] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < encoded.length) {
    let result = 1;
    let shift = 0;
    let byte: number;
    do {
      byte = encoded.charCodeAt(index++) - 63 - 1;
      result += byte << shift;
      shift += 5;
    } while (byte >= 0x1f);
    lat += result & 1 ? ~(result >> 1) : result >> 1;

    result = 1;
    shift = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63 - 1;
      result += byte << shift;
      shift += 5;
    } while (byte >= 0x1f);
    lng += result & 1 ? ~(result >> 1) : result >> 1;

    points.push([lat / factor, lng / factor]);
  }
  return points;
}
