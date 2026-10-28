# web-tests

The site's tests (the template's encryption and share-link encoding, the read limit and TTL rules over real SQLite with the migrations applied and a TTL-honouring KV, the API routes, the site's name and source link)

The test suite for **web**. It deploys nothing: its lane installs, builds and runs the tests.

|              |                      |
| ------------ | -------------------- |
| Type         | `turbo-package`      |
| Source       | `tests/web`          |
| Package      | `@app/web-tests`     |
| Environments | `dev`: `quick-check` |

## Depends on

- (none)

## Depended on by

- (none)
