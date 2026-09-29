import type { ReactNode } from "react";
import { SiteShell } from "../_components/site-shell";

/**
 * Same header/footer as marketing, but a plainer, denser content area —
 * account/dashboard UI, not landing-page motion.
 *
 * Route-group layouts have no URL segment of their own, so the generated
 * LayoutProps<'/route'> helper doesn't apply here — plain children prop.
 */
export default function AccountLayout({ children }: { children: ReactNode }) {
  return (
    <SiteShell>
      <div className="mx-auto w-full max-w-4xl flex-1 bg-[#FAF8F5] px-5 py-12 sm:px-8">
        {children}
      </div>
    </SiteShell>
  );
}
