# cloudflare-kv

Provisions the Cloudflare KV namespace the shared documents' ciphertext is kept in (stage and prod)

Terraform-managed infrastructure, planned and applied per environment by its CI lane.

|              |                                                                                                      |
| ------------ | ---------------------------------------------------------------------------------------------------- |
| Type         | `terraform`                                                                                          |
| Source       | `infra/terraform/cloudflare-kv`                                                                      |
| Environments | `stage`: `plan-only`, `apply` on a push to `main` · `prod`: `plan-only`, `apply` on a push to `main` |

## Depends on

- (none)

## Depended on by

- **web** — The secret-sharing site (Next.js on Cloudflare Workers + Static Assets via @opennextjs/cloudflare, per environment; the shared documents' ciphertext in KV, their read limits and expiries in D1)
