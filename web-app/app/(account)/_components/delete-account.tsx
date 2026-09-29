"use client";

import { useActionState, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { deleteAccount, type DeleteAccountState } from "../account/actions";

const initialState: DeleteAccountState = { error: null };

export function DeleteAccount() {
  const [confirming, setConfirming] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const [state, formAction, pending] = useActionState(deleteAccount, initialState);

  if (!confirming) {
    return (
      <Button
        type="button"
        variant="outline"
        className="border-destructive/40 text-destructive hover:bg-destructive/10"
        onClick={() => setConfirming(true)}
      >
        Delete account
      </Button>
    );
  }

  return (
    <form action={formAction} className="space-y-4">
      <p className="text-sm leading-relaxed text-muted-foreground">
        This permanently deletes your account, trips, groups, chat history, and
        photos. Type <span className="font-bold text-foreground">DELETE</span> to
        confirm.
      </p>
      <Input
        type="text"
        name="confirm"
        value={confirmText}
        onChange={(e) => setConfirmText(e.target.value)}
        placeholder="DELETE"
        aria-label="Type DELETE to confirm"
        className="max-w-xs border-destructive/40"
      />

      {state.error && (
        <Alert variant="destructive">
          <AlertDescription>{state.error}</AlertDescription>
        </Alert>
      )}

      <div className="flex items-center gap-3">
        <Button
          type="submit"
          variant="destructive"
          disabled={confirmText !== "DELETE" || pending}
        >
          {pending ? "Deleting…" : "Permanently delete"}
        </Button>
        <Button
          type="button"
          variant="ghost"
          onClick={() => {
            setConfirming(false);
            setConfirmText("");
          }}
        >
          Cancel
        </Button>
      </div>
    </form>
  );
}
