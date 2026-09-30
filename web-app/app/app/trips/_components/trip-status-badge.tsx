import type { TripStatus } from "@/lib/data/types";

const STYLES: Record<TripStatus, { label: string; className: string }> = {
  planned: { label: "Planned", className: "bg-slate-100 text-slate-700" },
  active: { label: "Active", className: "bg-emerald-100 text-emerald-800" },
  completed: { label: "Completed", className: "bg-blue-100 text-blue-800" },
  cancelled: { label: "Cancelled", className: "bg-red-100 text-red-700" },
};

export function TripStatusBadge({ status }: { status: TripStatus }) {
  const style = STYLES[status] ?? STYLES.planned;
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${style.className}`}
    >
      {style.label}
    </span>
  );
}
