import { redirect } from "next/navigation";

/** Account management now lives in the app shell. */
export default function AccountRedirect() {
  redirect("/app/profile/edit");
}
