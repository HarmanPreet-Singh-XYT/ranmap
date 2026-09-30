"use client";

import { toggleChecklistItem } from "../../actions";

/** A checkbox that submits its form as soon as it's toggled. */
export function ChecklistToggle({
  tripId,
  itemId,
  done,
}: {
  tripId: string;
  itemId: string;
  done: boolean;
}) {
  return (
    <form action={toggleChecklistItem}>
      <input type="hidden" name="trip_id" value={tripId} />
      <input type="hidden" name="item_id" value={itemId} />
      <input type="hidden" name="done" value={done ? "0" : "1"} />
      <input
        type="checkbox"
        defaultChecked={done}
        aria-label="Toggle packed"
        onChange={(event) => event.currentTarget.form?.requestSubmit()}
        className="size-4 accent-emerald-700"
      />
    </form>
  );
}
