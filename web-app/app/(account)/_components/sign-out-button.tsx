import { signOut } from "../actions";

export function SignOutButton() {
  return (
    <form action={signOut}>
      <button
        type="submit"
        className="text-sm text-[var(--color-ink-secondary)] transition-colors hover:text-[var(--color-danger)]"
      >
        Sign out
      </button>
    </form>
  );
}
