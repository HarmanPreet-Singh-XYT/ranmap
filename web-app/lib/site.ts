/**
 * Site-wide identity used for metadata, the sitemap and robots. The canonical
 * origin comes from NEXT_PUBLIC_SITE_URL so previews and production don't
 * advertise each other's URLs.
 */

export const siteUrl = (
  process.env.NEXT_PUBLIC_SITE_URL ?? "https://ranmap.app"
).replace(/\/+$/, "");

export const siteName = "Ranmap";

export const siteDescription =
  "The all-in-one group travel and convoy app: live 3D convoy radar, hands-free PTT radio, AI route co-pilot, and group pitstop voting.";
