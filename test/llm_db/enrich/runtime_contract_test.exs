defmodule LLMDB.Enrich.RuntimeContractTest do
  use ExUnit.Case, async: true

  alias LLMDB.Enrich.RuntimeContract
  alias LLMDB.{Model, Provider}

  describe "enrich_provider/1" do
    test "adds typed runtime defaults for executable providers" do
      provider =
        Provider.new!(%{
          id: :openai,
          env: ["OPENAI_API_KEY"],
          doc: "https://platform.openai.com/docs"
        })

      enriched = RuntimeContract.enrich_provider(provider)

      assert enriched.catalog_only == false
      assert enriched.runtime.base_url == "https://api.openai.com/v1"
      assert enriched.runtime.auth.type == "bearer"
      assert enriched.runtime.auth.env == ["OPENAI_API_KEY"]
      assert enriched.runtime.doc_url == "https://platform.openai.com/docs"
    end

    test "adds config schema for providers with required runtime placeholders" do
      provider =
        Provider.new!(%{
          id: :cloudflare_workers_ai,
          env: ["CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_API_KEY"]
        })

      enriched = RuntimeContract.enrich_provider(provider)

      assert enriched.catalog_only == false

      assert enriched.runtime.base_url ==
               "https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1"

      assert enriched.runtime.auth.type == "bearer"
      assert enriched.runtime.auth.env == ["CLOUDFLARE_API_KEY"]
      assert [%{name: "account_id", required: true}] = enriched.runtime.config_schema
    end

    test "marks unsupported providers catalog only" do
      provider = Provider.new!(%{id: :docs_only_provider})
      enriched = RuntimeContract.enrich_provider(provider)

      assert enriched.catalog_only == true
      assert enriched.runtime == nil
    end

    test "preserves incomplete authored runtime metadata so validation can fail loudly" do
      provider =
        Provider.new!(%{
          id: :custom_provider,
          runtime: %{auth: %{type: :bearer, env: ["CUSTOM_API_KEY"]}}
        })

      enriched = RuntimeContract.enrich_provider(provider)

      assert enriched.catalog_only == false
      assert enriched.runtime.auth.type == "bearer"
      assert enriched.runtime.base_url == nil
    end
  end

  describe "enrich_model/2" do
    test "derives responses-family execution from explicit wire protocol" do
      provider =
        Provider.new!(%{id: :openai, env: ["OPENAI_API_KEY"]})
        |> RuntimeContract.enrich_provider()

      model =
        Model.new!(%{
          id: "gpt-4.1",
          provider: :openai,
          extra: %{wire: %{protocol: "openai_responses"}}
        })

      enriched = RuntimeContract.enrich_model(model, provider)

      assert enriched.catalog_only == false
      assert enriched.execution.text.family == "openai_responses_compatible"
      assert enriched.execution.object.family == "openai_responses_compatible"
      assert enriched.execution.text.path == "/responses"
    end

    test "derives speech execution for dedicated tts models without adding text operations" do
      provider =
        Provider.new!(%{id: :openai, env: ["OPENAI_API_KEY"]})
        |> RuntimeContract.enrich_provider()

      model = Model.new!(%{id: "gpt-4o-mini-tts", provider: :openai})
      enriched = RuntimeContract.enrich_model(model, provider)

      assert enriched.catalog_only == false
      assert Map.has_key?(enriched.execution, :speech)
      refute Map.has_key?(enriched.execution, :text)
      refute Map.has_key?(enriched.execution, :object)
      assert enriched.execution.speech.family == "openai_speech"
    end

    test "keeps multimodal chat models on the text lane instead of misclassifying them as transcription" do
      provider =
        Provider.new!(%{id: :alibaba, env: ["DASHSCOPE_API_KEY"]})
        |> RuntimeContract.enrich_provider()

      model =
        Model.new!(%{
          id: "qwen3-omni-flash",
          provider: :alibaba,
          modalities: %{input: [:text, :image, :audio, :video], output: [:text, :audio]},
          capabilities: %{chat: true}
        })

      enriched = RuntimeContract.enrich_model(model, provider)

      assert enriched.catalog_only == false
      assert enriched.execution.text.family == "openai_chat_compatible"
      assert enriched.execution.object.family == "openai_chat_compatible"
      refute Map.has_key?(enriched.execution, :transcription)
    end

    test "marks models without a safe execution contract catalog only" do
      provider =
        Provider.new!(%{id: :google, env: ["GOOGLE_API_KEY"]})
        |> RuntimeContract.enrich_provider()

      model =
        Model.new!(%{
          id: "gemini-2.5-flash-image",
          provider: :google,
          modalities: %{input: [:text], output: [:image]}
        })

      enriched = RuntimeContract.enrich_model(model, provider)

      assert enriched.catalog_only == true
      assert enriched.execution == nil
    end
  end
end
