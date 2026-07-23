# botvinnik-sync worker

The server half of end-to-end-encrypted cross-device sync ([issue #203]). It is
a **dumb blob store**: it holds only ciphertext, addressed by an opaque `blobId`
the client derives from the user's sync phrase. There are no accounts and no
auth — knowing the id is the only capability, and it grants access to ciphertext
only. All crypto and all conflict-resolving merge logic live on the device
(`flutter/lib/stores/backup.dart`).

[issue #203]: https://github.com/quadrismegistus/botvinnik/issues/203

## API

| Route         | Success            | Failure                          |
| ------------- | ------------------ | -------------------------------- |
| `GET /b/:id`  | `200` body + ETag  | `404` if absent                  |
| `PUT /b/:id`  | `201`/`200` + ETag | `412` · `413` · `428` · `400`    |
| `GET /`       | `200` health       | —                                |

Compare-and-swap is HTTP-native and **mandatory** on `PUT`:

- **Create:** `If-None-Match: *` — `201`, or `412` if the blob already exists.
- **Update:** `If-Match: <etag>` — `200`, or `412` if it changed first (client
  re-GETs, re-merges, retries).
- Neither header → `428`; both → `400`.

Ciphertext is capped at **10 MB** (`413` past that). `blobId` must match
`^[A-Za-z0-9_-]{16,128}$`.

## Develop & test locally (no Cloudflare account)

```sh
npm install
npm test          # workerd + simulated R2, via @cloudflare/vitest-pool-workers
npm run dev       # local server at http://localhost:8787, simulated R2
./test/smoke.sh   # curl the create / update / 412 / 404 paths against `npm run dev`
```

## Deploy (needs a Cloudflare account)

```sh
npx wrangler login
npx wrangler r2 bucket create botvinnik-sync   # one-time
npm run deploy
```

The deployed URL becomes the client's single configurable sync endpoint (see the
`SyncService` base-URL constant, #203 M2+).
