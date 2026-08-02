# TraceScout Source Maps Upload — GitHub Action

Official GitHub Action for uploading **private source maps** to
[TraceScout](https://tracescout.com) so production stack traces symbolicate to
your original source. A thin wrapper around the published
[`@tracescout/cli`](https://www.npmjs.com/package/@tracescout/cli) — no
duplicated upload logic lives in this Action.

- Token via **GitHub Secrets only** — never echoed, redacted by the CLI in all
  output including `--debug`.
- Typed `::error` annotations + a safe step summary (counts and error codes —
  never source content, never the token).
- Retries with exponential backoff; idempotent re-runs; `dry-run` support.
- Source maps are uploaded **privately** — they never become publicly
  reachable through TraceScout.

## Usage

```yaml
- name: Build
  run: npm run build          # emits dist/**/*.js.map (hidden maps are fine)

- name: Upload source maps to TraceScout
  uses: Hananc86/tracescout-sourcemaps-action@v1
  with:
    project: ${{ vars.TRACESCOUT_PROJECT_ID }}
    release: ${{ github.sha }}
    dist: web
    path: dist
    url-prefix: "~/assets"
    auth-token: ${{ secrets.TRACESCOUT_SOURCEMAP_TOKEN }}
```

### Pinning

`@v1` is the moving major tag. For supply-chain-sensitive pipelines, **pin to
an immutable release tag or, best, a full commit SHA**:

```yaml
  uses: Hananc86/tracescout-sourcemaps-action@v1.0.0
  # or (strongest):
  uses: Hananc86/tracescout-sourcemaps-action@<full 40-char commit SHA>
```

Release tags are never moved or reused; `v1` is fast-forwarded only to
backwards-compatible releases.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `project` | yes | — | TraceScout project id |
| `release` | yes | — | Release identifying this build (must match `TraceScout.init`'s `release`) |
| `path` | yes | — | File or directory containing the built `*.js.map` files |
| `auth-token` | yes | — | Scoped upload token — pass from a GitHub Secret |
| `dist` | no | `""` | Build variant (e.g. `web`) |
| `url-prefix` | no | `~/` | Host-agnostic prefix for each artifact's URL identity |
| `sources-content-policy` | no | server default (`strip`) | `strip` \| `retain` \| `reject` |
| `dry-run` | no | `false` | Plan without uploading |
| `retries` | no | `3` | Retry attempts per map |
| `cli-version` | no | `latest` | `@tracescout/cli` version to run (pin for reproducibility) |

## Exit behavior

Mirrors the CLI: success `0`, upload failure `1`, usage error `2`,
auth/feature-unavailable `3`. Failures annotate the run with the typed error
code (`unauthorized`, `identity_conflict`, `upload_unavailable`, …).

## Getting an upload token

Create a scoped source-map upload token in your TraceScout project settings
(Settings → Source Maps) and store it as a repository secret. The token can
only upload source maps for that project — it grants no read access.

Docs: https://docs.tracescout.com/docs/guides/source-maps

## License

Apache-2.0 (see `LICENSE`). TraceScout names and logos are trademarks of
TraceScout — no trademark rights are granted.
