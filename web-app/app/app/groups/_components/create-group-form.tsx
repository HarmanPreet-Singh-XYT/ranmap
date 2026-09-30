"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { createGroup, type GroupActionState } from "../actions";

const initialState: GroupActionState = { error: null };

export function CreateGroupForm() {
  const [state, action, pending] = useActionState(createGroup, initialState);

  return (
    <form action={action} className="space-y-2">
      <div className="flex gap-2">
        <input
          name="name"
          required
          maxLength={60}
          placeholder="New group name…"
          className="h-9 flex-1 rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
        />
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Creating…" : "Create group"}
        </Button>
      </div>
      {state.error && <p className="text-xs text-red-700">{state.error}</p>}
    </form>
  );
}
