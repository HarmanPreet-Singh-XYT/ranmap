import { decodePolyline } from "@/lib/data/geo";

const W = 200;
const H = 120;
const PAD = 16;

/**
 * A lightweight route map: decodes the trip's encoded polyline and draws it as
 * an SVG. No tiles or tokens, so it renders anywhere; when a trip has no
 * geometry yet it falls back to a decorative route so cards never look empty.
 */
export function RoutePreview({
  polyline,
  points: providedPoints,
  className = "",
}: {
  polyline?: string | null;
  /** Raw [lat, lng] pairs, used instead of a polyline when provided. */
  points?: [number, number][];
  className?: string;
}) {
  const points =
    providedPoints && providedPoints.length >= 2
      ? providedPoints
      : decodePolyline(polyline);

  if (points.length < 2) {
    return (
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className={className}
        preserveAspectRatio="xMidYMid meet"
        aria-hidden
      >
        <path
          d="M20 96 C60 96 60 40 100 40 C140 40 140 24 180 24"
          fill="none"
          className="stroke-emerald-600/40"
          strokeWidth="2.5"
          strokeLinecap="round"
          strokeDasharray="6 7"
        />
        <circle cx="20" cy="96" r="5" className="fill-emerald-600" />
        <circle cx="180" cy="24" r="5" className="fill-slate-300" />
      </svg>
    );
  }

  const lats = points.map((p) => p[0]);
  const lngs = points.map((p) => p[1]);
  const minLat = Math.min(...lats);
  const maxLat = Math.max(...lats);
  const minLng = Math.min(...lngs);
  const maxLng = Math.max(...lngs);

  const spanLat = maxLat - minLat || 1e-6;
  const spanLng = maxLng - minLng || 1e-6;
  const scale = Math.min((W - 2 * PAD) / spanLng, (H - 2 * PAD) / spanLat);
  const offsetX = (W - spanLng * scale) / 2;
  const offsetY = (H - spanLat * scale) / 2;

  // Flip latitude so north is up.
  const xy = (lat: number, lng: number): [number, number] => [
    offsetX + (lng - minLng) * scale,
    H - (offsetY + (lat - minLat) * scale),
  ];

  const path = points
    .map((p, i) => {
      const [x, y] = xy(p[0], p[1]);
      return `${i === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`;
    })
    .join(" ");

  const [startX, startY] = xy(points[0][0], points[0][1]);
  const [endX, endY] = xy(points[points.length - 1][0], points[points.length - 1][1]);

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      className={className}
      preserveAspectRatio="xMidYMid meet"
      aria-hidden
    >
      <path
        d={path}
        fill="none"
        className="stroke-emerald-600"
        strokeWidth="3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx={startX} cy={startY} r="5" className="fill-emerald-600" />
      <circle
        cx={startX}
        cy={startY}
        r="8"
        className="fill-none stroke-emerald-600/30"
        strokeWidth="2"
      />
      <circle cx={endX} cy={endY} r="5" className="fill-slate-800" />
    </svg>
  );
}
