import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

// The template's own lint config was `next/core-web-vitals` (its
// .eslintrc.json), here in eslint-config-next 16's flat form with its
// TypeScript rules beside it.
export default defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    rules: {
      // The unseal page reads the link's fragment from an effect; the rule
      // that flags it arrived with eslint-config-next 16, after the template
      // was written.
      "react-hooks/set-state-in-effect": "off",
    },
  },
  globalIgnores([".next/**", ".open-next/**", "next-env.d.ts", "cloudflare-env.d.ts"]),
]);
