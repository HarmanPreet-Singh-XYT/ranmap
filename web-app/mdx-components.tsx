import type { MDXComponents } from "mdx/types";

/**
 * Typography for MDX-authored legal/policy content. Keeps the same editorial
 * look the hand-written legal pages had (display font headings, relaxed body
 * copy) so switching the source to MDX doesn't change the design.
 */
const components: MDXComponents = {
  h2: ({ children }) => (
    <h2 className="mt-14 font-display text-xl font-bold text-slate-900">
      {children}
    </h2>
  ),
  h3: ({ children }) => (
    <h3 className="mt-8 font-display text-base font-bold text-slate-900">
      {children}
    </h3>
  ),
  p: ({ children }) => (
    <p className="mt-4 text-sm leading-relaxed text-slate-600">{children}</p>
  ),
  ul: ({ children }) => <ul className="mt-4 space-y-3">{children}</ul>,
  li: ({ children }) => (
    <li className="flex gap-3 text-sm leading-relaxed text-slate-600">
      <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-600" />
      <span>{children}</span>
    </li>
  ),
  a: ({ children, href }) => (
    <a
      href={href}
      className="font-medium text-emerald-700 underline underline-offset-2 hover:text-emerald-800"
    >
      {children}
    </a>
  ),
  strong: ({ children }) => (
    <strong className="font-semibold text-slate-800">{children}</strong>
  ),
};

export function useMDXComponents(): MDXComponents {
  return components;
}
