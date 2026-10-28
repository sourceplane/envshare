import { getCloudflareContext } from "@opennextjs/cloudflare"
import "server-only"

/**
 * The Worker's bindings and vars for this request (wrangler.jsonc). `next
 * dev` reaches the same through wrangler's platform proxy.
 */
export function env(): CloudflareEnv {
  return getCloudflareContext().env
}
