import {
  llmdb,
  parseModelSpec,
  type KnownProviderId,
  type Model,
} from "../src/index.js";

const providerId: KnownProviderId = "openai";
const providerIds: readonly KnownProviderId[] = llmdb.providerIds();
const model: Promise<Model> = llmdb.get("openai:gpt-5.4");
const models: Promise<readonly Model[]> = llmdb.models(providerId);
const parsed = parseModelSpec("gpt-5.4@openai");

model.then((value) => value.capabilities?.tools.enabled);
models.then((values) => values.at(0)?.pricing?.components.at(0)?.rate);
providerIds.at(0);
parsed.providerId;
