"use client";

import multiavatar from "@multiavatar/multiavatar";
import { cn } from "@/lib/utils";
import { customAvatarUrl, isCustomAvatar } from "@/lib/avatar";

/**
 * Renders a profile avatar. Uploaded photos render from the public bucket;
 * anything else is treated as a Multiavatar seed, matching the mobile app
 * (`lib/core/widgets/avatar_view.dart`).
 */
export function AvatarView({
  seed,
  className,
}: {
  seed: string | null;
  className?: string;
}) {
  if (isCustomAvatar(seed)) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={customAvatarUrl(seed as string)}
        alt=""
        className={cn("h-full w-full object-cover", className)}
      />
    );
  }

  // Generated locally from the user's own seed — no untrusted markup.
  const svg = multiavatar(seed && seed.length > 0 ? seed : "default");
  return (
    <span
      className={cn("block h-full w-full [&>svg]:h-full [&>svg]:w-full", className)}
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}
