import type { MigrationManifest } from "./types.js";

// Every migration the runner applies, in order, with the sha256 of its file.
// `pnpm --filter @saas/db run manifest:check` verifies the checksums;
// `manifest:fix` rewrites them after a migration file changes (only ever
// before that migration has been applied anywhere — an applied migration's
// checksum is immutable).
export const manifest: MigrationManifest = {
  version: 1,
  migrations: [
    {
      id: "000_control_baseline",
      context: "control",
      path: "000_control/up.sql",
      checksum:
        "c7f11499fa82d6fd2baa1af7fc75eeb73cd7be252af2e56841509c66001d638b",
      description:
        "Baseline control migration — creates the migration tracking schema",
    },
    {
      id: "010_secrets",
      context: "app",
      path: "010_secrets/up.sql",
      checksum:
        "ffc2ec65ebdc44eb2faceb68ac0f6d1a53a82be4c1d94681fd4db4cfc3c653f0",
      description:
        "The shared documents' read limits and expiries (the ciphertext is in Workers KV) and the site's read and write counters",
    },
  ],
};
