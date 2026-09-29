import Link from "next/link";
import { Download, Smartphone, ArrowRight, ShieldCheck, Sparkles } from "lucide-react";

// Real store listings, from env, so the badges never point somewhere unrelated.
// When a URL isn't configured the badge is omitted rather than shipped dead.
const APP_STORE_URL = process.env.NEXT_PUBLIC_APP_STORE_URL;
const PLAY_STORE_URL = process.env.NEXT_PUBLIC_PLAY_STORE_URL;

export function DownloadCta() {
  return (
    <section id="download" className="relative py-28 border-t border-[#E6E3DA] overflow-hidden bg-white">
      {/* Background glow */}
      <div className="pointer-events-none absolute bottom-0 left-1/2 -z-10 h-[500px] w-[900px] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,_rgba(21,128,61,0.08)_0%,_transparent_70%)] blur-3xl" />

      <div className="mx-auto max-w-5xl px-5 sm:px-8 text-center">
        <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-emerald-800">
          <Sparkles className="h-4 w-4 text-emerald-700" />
          <span>Available on iOS, Android & Web Console</span>
        </div>

        <h2 className="mt-5 font-display text-4xl font-extrabold tracking-tight text-slate-900 sm:text-6xl">
          Ready to Hit the Open Road?
        </h2>
        <p className="mx-auto mt-4 max-w-2xl text-base sm:text-lg text-slate-600 font-normal leading-relaxed">
          Start your next drive in sync. Download the app or plan your full convoy route directly in the web browser.
        </p>

        {/* Action Buttons & Badges */}
        <div className="mt-10 flex flex-wrap items-center justify-center gap-4">
          <Link
            href="/signup"
            className="flex items-center gap-2.5 rounded-full bg-emerald-700 px-8 py-4 text-sm font-bold text-white uppercase tracking-wider shadow-md transition-all hover:bg-emerald-800 hover:scale-105"
          >
            <span>Launch Web App Free</span>
            <ArrowRight className="h-4 w-4" />
          </Link>

          {APP_STORE_URL && (
            <a
              href={APP_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-3 rounded-full border border-[#E6E3DA] bg-[#FAF8F5] px-6 py-3.5 text-xs font-semibold text-slate-900 shadow-xs transition-all hover:bg-white hover:border-slate-400 hover:scale-[1.02]"
            >
              <Smartphone className="h-4 w-4 text-slate-700" />
              <div className="text-left">
                <span className="block text-[10px] text-slate-500 uppercase tracking-wider">Download on</span>
                <span className="text-sm font-bold text-slate-900">Apple App Store</span>
              </div>
            </a>
          )}

          {PLAY_STORE_URL && (
            <a
              href={PLAY_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-3 rounded-full border border-[#E6E3DA] bg-[#FAF8F5] px-6 py-3.5 text-xs font-semibold text-slate-900 shadow-xs transition-all hover:bg-white hover:border-slate-400 hover:scale-[1.02]"
            >
              <Download className="h-4 w-4 text-emerald-700" />
              <div className="text-left">
                <span className="block text-[10px] text-slate-500 uppercase tracking-wider">Get it on</span>
                <span className="text-sm font-bold text-slate-900">Google Play Store</span>
              </div>
            </a>
          )}
        </div>

        {/* Reassurance strip */}
        <div className="mt-12 flex flex-wrap items-center justify-center gap-6 text-xs text-slate-500 font-medium">
          <span className="flex items-center gap-1.5">
            <ShieldCheck className="h-4 w-4 text-emerald-700" />
            No credit card required
          </span>
          <span>·</span>
          <span>Instant convoy invite links</span>
          <span>·</span>
          <span>Free plan forever</span>
        </div>
      </div>
    </section>
  );
}
