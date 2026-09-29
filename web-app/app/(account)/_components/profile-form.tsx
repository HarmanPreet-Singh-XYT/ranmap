"use client";

import { useActionState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { updateProfile, type ProfileActionState } from "../account/actions";
import { AvatarUpload } from "./avatar-upload";

const initialState: ProfileActionState = { error: null, saved: false };

export function ProfileForm({
  userId,
  username,
  displayName,
  avatarId,
}: {
  userId: string;
  username: string;
  displayName: string | null;
  avatarId: string;
}) {
  const [state, formAction, pending] = useActionState(updateProfile, initialState);

  return (
    <div className="space-y-6">
      <AvatarUpload userId={userId} avatarId={avatarId} />

      <form action={formAction} className="space-y-5">
        <div className="space-y-1.5">
          <Label htmlFor="username">Username</Label>
          <Input
            id="username"
            name="username"
            type="text"
            required
            minLength={3}
            maxLength={24}
            pattern="[a-zA-Z0-9_]+"
            defaultValue={username}
          />
          <p className="text-xs text-muted-foreground">
            Letters, numbers, and underscores only.
          </p>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="display_name">Display name</Label>
          <Input
            id="display_name"
            name="display_name"
            type="text"
            maxLength={60}
            defaultValue={displayName ?? ""}
            placeholder="Shown to your crew instead of your username"
          />
        </div>

        {state.error && (
          <Alert variant="destructive">
            <AlertDescription>{state.error}</AlertDescription>
          </Alert>
        )}
        {state.saved && !state.error && (
          <Alert>
            <AlertDescription>Profile updated.</AlertDescription>
          </Alert>
        )}

        <Button type="submit" disabled={pending}>
          {pending ? "Saving…" : "Save changes"}
        </Button>
      </form>
    </div>
  );
}
