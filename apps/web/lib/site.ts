// The site's identity, written once. The title, the header, the footer, the
// deploy page and the Open Graph card read SITE_NAME; the GitHub links are
// SOURCE_URL. A product built from this baseline gets both rewritten to its
// own name and repository at instantiation, so keep them literal and on one
// line each.
export const SITE_NAME = "EnvShare"
export const SOURCE_URL = "https://github.com/sourceplane/envshare"

/**
 * This environment's public origin, no trailing slash. Each build sets
 * NEXT_PUBLIC_SITE_URL to its environment's SITE_URL (intent.yaml) or its
 * workers.dev URL (component.yaml's buildCommand); the Open Graph links are
 * built on it.
 */
export function siteUrl(): string {
  return (process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000").replace(/\/+$/, "")
}
