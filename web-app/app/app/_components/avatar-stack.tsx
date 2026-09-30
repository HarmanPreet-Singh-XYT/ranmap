import { AvatarView } from "@/app/(account)/_components/avatar-view";
import type { PublicProfile } from "@/lib/data/types";

/** Overlapping member avatars, with a "+N" chip when there are more. */
export function AvatarStack({
  people,
  max = 4,
  size = 28,
}: {
  people: PublicProfile[];
  max?: number;
  size?: number;
}) {
  const shown = people.slice(0, max);
  const extra = people.length - shown.length;
  const style = { width: size, height: size };

  return (
    <div className="flex items-center">
      {shown.map((person) => (
        <span
          key={person.id}
          style={style}
          className="-ml-2 flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50 ring-2 ring-white first:ml-0"
          title={person.display_name || person.username}
        >
          <AvatarView seed={person.avatar_id ?? "default"} />
        </span>
      ))}
      {extra > 0 && (
        <span
          style={style}
          className="-ml-2 flex shrink-0 items-center justify-center rounded-full bg-slate-200 text-[10px] font-bold text-slate-600 ring-2 ring-white"
        >
          +{extra}
        </span>
      )}
    </div>
  );
}
