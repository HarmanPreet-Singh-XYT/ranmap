import { signOut } from "../actions";

export function SignOutButton() {
  return (
    <form action={signOut}>
      <button
        type="submit"
        className="text-sm font-semibold text-slate-600 transition-colors hover:text-red-700"
      >
        Sign out
      </button>
    </form>
  );
}
