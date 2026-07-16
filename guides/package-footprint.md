# Package Footprint

The packaged catalog uses deterministic compact JSON. This changes only JSON
whitespace: decoded keys, values, array order, schema version, and snapshot ID
remain unchanged.

## Size comparison

Measured from the same 2026-07 packaged snapshot and package source tree with:

```shell
wc -c priv/llm_db/snapshot.json
gzip -n -c priv/llm_db/snapshot.json | wc -c
mix hex.build
```

| Artifact | Pretty JSON | Compact package | Change |
| --- | ---: | ---: | ---: |
| Raw `snapshot.json` | 12,198,384 bytes | 6,325,229 bytes | -48.1% |
| Gzip (`gzip -n`) | 582,088 bytes | 455,025 bytes | -21.8% |
| Hex archive | 756,224 bytes | 623,616 bytes | -17.5% |

These measurements are release-audit evidence, not fixed size budgets; catalog
growth will change them.

## Hex package manifest

The package deliberately includes:

- `lib` and `mix.exs` for runtime code and supported Mix tasks;
- `priv/llm_db/snapshot.json` for zero-network catalog use;
- `config` for the repository-maintainer task defaults retained during the
  compatibility window;
- `guides`, `README.md`, and `CHANGELOG.md` for HexDocs and release history;
- `LICENSE` for licensing.

Repository-only contributor instructions (`AGENTS.md`, `usage-rules.md`) and
the repository formatter configuration (`.formatter.exs`) are excluded. No
runtime module, supported task, guide, source configuration, license, or
packaged metadata is removed.
