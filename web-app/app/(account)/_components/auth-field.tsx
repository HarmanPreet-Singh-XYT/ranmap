export function AuthField({
  label,
  ...props
}: { label: string } & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-medium text-[var(--color-ink)]">
        {label}
      </span>
      <input
        {...props}
        className="w-full rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-background)] px-3.5 py-2 text-sm text-[var(--color-ink)] outline-none transition-colors focus:border-[var(--color-ink)]"
      />
    </label>
  );
}
