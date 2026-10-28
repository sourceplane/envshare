# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`envshare/`](./envshare/) | **ES** | In progress (ES0) | EnvShare — share environment variables through a link only its holder can read, AES-GCM in the browser — on Cloudflare Workers with the ciphertext in KV under its TTL and the read limits in D1, spent atomically, and an Orun baseline that instantiates it in one landing (ES2) |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
