# Snapshot Formats and Sparse v2 Rollout

LLM DB reads snapshot schema v1 and the opt-in sparse schema v2. Both decode
through the same integrity, structural validation, bounded atom-decoding, and
catalog construction boundaries. They produce the same `LLMDB.Provider` and
`LLMDB.Model` values.

The packaged `priv/llm_db/snapshot.json`, normal `mix llm_db.build` output, and
published GitHub Release snapshots remain schema v1 in this minor release.
`LLMDB.Snapshot.schema_version/0` therefore continues to return `1`.
`LLMDB.Snapshot.sparse_schema_version/0` returns `2`.

## Sparse encoding rules

Schema v2 only omits values at enumerated provider and model fields. It does not
walk arbitrary maps or remove values from `extra` data.

| Scope | Omitted value | Fields |
| --- | --- | --- |
| Provider | `null` | `alias_of`, `base_url`, `config_schema`, `doc`, `env`, `extra`, `name`, `pricing_defaults`, `runtime` |
| Provider | `false` | `catalog_only` |
| Provider | `[]` | `exclude_models` |
| Model | `null` | `base_url`, `capabilities`, `cost`, `doc_url`, `execution`, `extra`, `family`, `knowledge`, `last_updated`, `lifecycle`, `limits`, `modalities`, `model`, `name`, `pricing`, `provider_model_id`, `release_date`, `tags` |
| Model | `false` | `catalog_only`, `deprecated`, `retired` |
| Model | `[]` | `aliases` |

An omitted v2 field expands to the value in this table before structural
validation and catalog construction. Required identity fields are never
omitted. An explicit provider `exclude_models: null` is preserved because
absence defaults to `[]`; those two values are observably different. Unknown
keys, unknown false/null values, nested `extra` data, and array order pass
through unchanged.

Snapshot IDs address the encoded representation. A v1 document and its
semantically equivalent sparse v2 document therefore have different IDs.
Integrity is checked against the sparse wire shape before expansion. Encoding
an expanded v2 document applies the sparse rules again, so verified v2
documents remain deterministic and byte-stable across read/write round trips.

## Opt-in evaluation

Build a side-by-side sparse artifact with:

```bash
mix llm_db.build --schema-version 2
```

The default output is `_build/llm_db/snapshot-v2/snapshot.json`. Use
`--output-dir` to select another local directory. The task rejects
`--schema-version 2 --install`, and `mix llm_db.snapshot.publish` continues to
publish v1. This prevents an older consumer from receiving a representation it
cannot decode.

For programmatic evaluation, pass `schema_version: 2` to
`LLMDB.Snapshot.from_engine_snapshot/2` or convert a canonical v1 document with
`LLMDB.Snapshot.to_sparse/1`. Existing `encode`, `decode`, `read`, `write!`,
`prepare`, and `verify` calls accept both versions.

## Rollout gate

A future minor release may dual-publish v2 under a distinct asset name while
keeping `snapshot.json` on v1. Switching the packaged or primary published
artifact requires all of the following evidence:

1. the minimum supported llm_db reader can load v2 or consumers negotiate the
   alternate asset explicitly;
2. snapshot fetch, cache, history rebuild, compile-embed, and integrity paths
   pass the shared v1/v2 compatibility suite;
3. release metadata declares the wire schema/minimum reader requirement;
4. one release has carried dual artifacts and migration notes; and
5. package-size and load-time results justify the representation switch.

The v1 reader remains supported when that switch occurs. Removing it would
require a separate breaking-release decision.
