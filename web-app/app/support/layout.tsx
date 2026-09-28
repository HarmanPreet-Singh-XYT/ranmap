import type { ReactNode } from "react";
import { SiteShell } from "../_components/site-shell";

export default function SupportLayout({ children }: { children: ReactNode }) {
  return <SiteShell>{children}</SiteShell>;
}
