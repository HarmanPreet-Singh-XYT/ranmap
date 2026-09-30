import { Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listTripChecklist } from "@/lib/data/trips";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { addChecklistItem, deleteChecklistItem } from "../../actions";
import { ChecklistToggle } from "./checklist-toggle";

export default async function TripChecklistPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const items = await listTripChecklist(supabase, id);
  const doneCount = items.filter((i) => i.done).length;

  return (
    <div className="space-y-4">
      <Card size="sm">
        <CardContent>
          <form action={addChecklistItem} className="flex gap-2">
            <input type="hidden" name="trip_id" value={id} />
            <input
              name="label"
              required
              maxLength={80}
              placeholder="Add an item to pack…"
              className="h-9 flex-1 rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
            />
            <Button type="submit" size="sm">
              Add
            </Button>
          </form>
        </CardContent>
      </Card>

      {items.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            Your packing list is empty.
          </CardContent>
        </Card>
      ) : (
        <>
          <p className="text-xs font-semibold text-slate-500">
            {doneCount} of {items.length} packed
          </p>
          <ul className="space-y-2">
            {items.map((item) => (
              <li key={item.id}>
                <Card size="sm">
                  <CardContent className="flex items-center gap-3">
                    <ChecklistToggle tripId={id} itemId={item.id} done={item.done} />
                    <span
                      className={`min-w-0 flex-1 truncate text-sm ${
                        item.done ? "text-muted-foreground line-through" : "text-slate-800"
                      }`}
                    >
                      {item.label}
                    </span>
                    <form action={deleteChecklistItem}>
                      <input type="hidden" name="trip_id" value={id} />
                      <input type="hidden" name="item_id" value={item.id} />
                      <button
                        type="submit"
                        aria-label={`Remove ${item.label}`}
                        className="flex size-7 items-center justify-center rounded-md text-slate-400 hover:bg-red-50 hover:text-red-700"
                      >
                        <Trash2 className="size-4" aria-hidden />
                      </button>
                    </form>
                  </CardContent>
                </Card>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}
