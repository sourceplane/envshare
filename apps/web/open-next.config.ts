// OpenNext Cloudflare adapter config.
//
// Nothing here is incrementally regenerated: the home page renders per
// request (`dynamic = "force-dynamic"`, it reads its counters from D1) and so
// does every API route. The static-assets incremental cache serves what the
// build pre-rendered (the share, unseal and deploy pages, the 404) straight
// from the Worker's static assets — read only, nothing to provision. A page
// that revalidates (ISR, `revalidateTag`) swaps this for the R2 incremental
// cache plus a tag cache.
import { defineCloudflareConfig } from "@opennextjs/cloudflare/config";
import staticAssetsIncrementalCache from "@opennextjs/cloudflare/overrides/incremental-cache/static-assets-incremental-cache";

export default defineCloudflareConfig({
  incrementalCache: staticAssetsIncrementalCache,
});
