import { redirect } from "next/navigation";

/** Stats now live in the app shell. */
export default function StatsRedirect() {
  redirect("/app/profile/stats");
}
