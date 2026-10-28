import { defineConfig } from "vitest/config";
import * as path from "node:path";

const web = path.resolve(__dirname, "../../apps/web");

export default defineConfig({
  resolve: {
    // The app's own import roots (apps/web/tsconfig.json: baseUrl "." and
    // the @components path), so the routes and modules run here unchanged.
    alias: [
      { find: /^@web\//, replacement: `${web}/` },
      { find: /^lib\//, replacement: `${web}/lib/` },
      { find: /^pkg\//, replacement: `${web}/pkg/` },
      { find: /^util\//, replacement: `${web}/util/` },
      { find: /^@components\//, replacement: `${web}/app/components/` },
      // A marker module Next resolves for server code; outside Next it throws on import.
      { find: /^server-only$/, replacement: path.resolve(__dirname, "src/support/server-only.ts") },
    ],
  },
  test: {
    include: ["src/**/*.test.ts", "src/**/*.test.tsx"],
    environment: "node",
  },
});
