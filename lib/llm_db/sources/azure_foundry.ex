defmodule LLMDB.Sources.AzureFoundry do
  @moduledoc """
  Remote source for Azure AI Foundry model catalog.

  Fetches model metadata from Azure AI Foundry's public catalog API,
  filters to serverless (standard-paygo) models, and transforms to
  canonical format.

  - `pull/1` fetches data from the catalog API and caches locally
  - `load/1` reads from cached file (no network call)

  ## Options

  - `:include_families` - List of model name prefixes to include (case-insensitive).
    Empty list or omitted means include all standard-paygo models.
  - `:req_opts` - Additional Req options for testing

  ## Usage

      mix llm_db.pull --source azure_foundry

      {:ok, data} = AzureFoundry.load(%{include_families: ["grok", "phi-4"]})
  """

  @behaviour LLMDB.Source

  require Logger

  @api_url "https://ai.azure.com/api/eastus/ux/v1.0/entities/crossRegion"
  @default_cache_dir "priv/llm_db/remote"
  @cache_id "azure-foundry"
  @page_size 200

  @registries [
    "azure-openai",
    "azureml",
    "azureml-meta",
    "azureml-mistral",
    "azureml-cohere",
    "azureml-deepseek",
    "azureml-xai",
    "azureml-anthropic",
    "azureml-moonshotai",
    "azureml-nvidia",
    "azureml-ai21",
    "azureml-alibaba"
  ]

  @chat_tasks ["chat-completion", "completions", "text-generation"]
  @embedding_tasks ["embeddings", "embedding"]
  @image_tasks ["text-to-image", "image-to-image"]

  @known_modalities %{
    "text" => :text,
    "image" => :image,
    "audio" => :audio,
    "video" => :video,
    "code" => :code,
    "pdf" => :pdf
  }

  @impl true
  def pull(opts) do
    req_opts = Map.get(opts, :req_opts, [])
    cache_dir = get_cache_dir()
    cache_path = Path.join(cache_dir, "#{@cache_id}.json")
    manifest_path = Path.join(cache_dir, "#{@cache_id}.manifest.json")

    case fetch_all_pages(req_opts) do
      {:ok, models} ->
        bin = Jason.encode!(models, pretty: true)
        write_cache(cache_path, manifest_path, bin)
        {:ok, cache_path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def load(opts) do
    cache_dir = get_cache_dir()
    cache_path = Path.join(cache_dir, "#{@cache_id}.json")

    case File.read(cache_path) do
      {:ok, bin} ->
        case Jason.decode(bin) do
          {:ok, decoded} ->
            families = Map.get(opts, :include_families, [])
            {:ok, transform(decoded, include_families: families)}

          {:error, err} ->
            {:error, {:json_error, err}}
        end

      {:error, :enoent} ->
        {:error, :no_cache}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Transforms Azure Foundry catalog data to canonical Zoi format.

  Accepts a list of raw model entities from the API. Filters to
  `standard-paygo` offer type, then transforms each model to
  canonical format.

  ## Options

  - `:include_families` - List of model name prefixes for filtering
    (case-insensitive prefix match). Empty or omitted includes all.
  """
  def transform(models, opts \\ []) when is_list(models) do
    families = Keyword.get(opts, :include_families, [])

    canonical_models =
      models
      |> Enum.filter(&paygo?/1)
      |> Enum.filter(&family_match?(&1, families))
      |> Enum.map(&transform_model/1)

    %{
      "azure_foundry" => %{
        id: :azure_foundry,
        name: "Azure AI Foundry",
        models: canonical_models
      }
    }
  end

  @openai_registry "azure-openai"

  defp paygo?(model) do
    registry = model["entityResourceName"]

    if registry == @openai_registry do
      true
    else
      offers =
        get_in(model, ["annotations", "systemCatalogData", "azureOffers"]) || []

      "standard-paygo" in offers
    end
  end

  defp family_match?(_model, []), do: true

  defp family_match?(model, families) do
    id = model_id(model)

    Enum.any?(families, fn prefix ->
      String.starts_with?(id, String.downcase(prefix))
    end)
  end

  defp transform_model(model) do
    catalog = get_in(model, ["annotations", "systemCatalogData"]) || %{}
    tasks = Map.get(catalog, "inferenceTasks") || []
    capabilities = Map.get(catalog, "modelCapabilities") || []
    input_mods = Map.get(catalog, "inputModalities")
    output_mods = Map.get(catalog, "outputModalities")

    type = derive_type(tasks)

    %{
      id: model_id(model),
      provider: :azure_foundry,
      name: Map.get(catalog, "displayName", model_id(model)),
      type: type,
      modalities: build_modalities(input_mods, output_mods, type),
      limits: build_limits(catalog),
      extra: build_extra(catalog, capabilities, model)
    }
  end

  defp model_id(model) do
    model
    |> get_in(["annotations", "name"])
    |> to_string()
    |> String.downcase()
  end

  defp derive_type(tasks) do
    cond do
      Enum.any?(tasks, &(&1 in @chat_tasks)) -> :chat
      Enum.any?(tasks, &(&1 in @embedding_tasks)) -> :embedding
      Enum.any?(tasks, &(&1 in @image_tasks)) -> :image_generation
      "text-classification" in tasks -> :rerank
      true -> :other
    end
  end

  defp build_modalities(_, _, :embedding) do
    %{input: [:text], output: [:embedding]}
  end

  defp build_modalities(nil, nil, _type), do: %{input: [], output: []}

  defp build_modalities(input, output, _type) do
    input_atoms = atomize_modalities(input || [])
    output_atoms = atomize_modalities(output)

    output_atoms =
      if is_nil(output_atoms) or output_atoms == [], do: input_atoms, else: output_atoms

    %{input: input_atoms, output: output_atoms}
  end

  defp atomize_modalities(nil), do: nil

  defp atomize_modalities(list) when is_list(list) do
    Enum.map(list, fn s -> Map.get(@known_modalities, s, :other) end)
  end

  defp build_limits(catalog) do
    limits = %{}

    limits =
      case Map.get(catalog, "textContextWindow") do
        val when is_integer(val) and val > 0 -> Map.put(limits, :context, val)
        _ -> limits
      end

    case Map.get(catalog, "maxOutputTokens") do
      val when is_integer(val) and val > 0 -> Map.put(limits, :output, val)
      _ -> limits
    end
  end

  defp build_extra(catalog, capabilities, model) do
    extra = %{
      publisher: Map.get(catalog, "publisher"),
      registry: Map.get(model, "entityResourceName")
    }

    extra =
      case Map.get(catalog, "license") do
        nil -> extra
        license -> Map.put(extra, :license, license)
      end

    extra =
      if capabilities != [] do
        Map.put(extra, :capabilities, capabilities)
      else
        extra
      end

    tasks = Map.get(catalog, "inferenceTasks", [])
    maybe_put_wire_protocol(extra, tasks, capabilities)
  end

  defp maybe_put_wire_protocol(extra, tasks, _capabilities) do
    cond do
      "messages" in tasks ->
        Map.put(extra, :wire_protocol, :anthropic_messages)

      "responses" in tasks ->
        Map.put(extra, :wire_protocol, :openai_responses)

      Enum.any?(tasks, &(&1 in @chat_tasks)) ->
        Map.put(extra, :wire_protocol, :openai_completion)

      true ->
        extra
    end
  end

  # Pull helpers

  defp fetch_all_pages(req_opts, continuation_token \\ nil, acc \\ []) do
    body = build_request_body(continuation_token)

    headers = [{"user-agent", "AzureAiStudio"}]
    merged_headers = headers ++ Keyword.get(req_opts, :headers, [])
    merged_opts = Keyword.put(req_opts, :headers, merged_headers)

    case Req.post(@api_url, [json: body] ++ merged_opts) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        ier = Map.get(resp_body, "indexEntitiesResponse", %{})
        entities = Map.get(ier, "value", [])
        acc = Enum.reverse(entities) ++ acc

        case Map.get(ier, "continuationToken") do
          nil -> {:ok, Enum.reverse(acc)}
          "" -> {:ok, Enum.reverse(acc)}
          token -> fetch_all_pages(req_opts, token, acc)
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_request_body(continuation_token) do
    resource_ids =
      Enum.map(@registries, fn registry ->
        %{"resourceId" => registry, "entityContainerType" => "Registry"}
      end)

    index_request = %{
      "filters" => [
        %{"field" => "type", "operator" => "eq", "values" => ["models"]},
        %{"field" => "kind", "operator" => "eq", "values" => ["Versioned"]},
        %{"field" => "labels", "operator" => "eq", "values" => ["latest"]}
      ],
      "pageSize" => @page_size,
      "skip" => nil,
      "continuationToken" => continuation_token
    }

    %{
      "resourceIds" => resource_ids,
      "indexEntitiesRequest" => index_request
    }
  end

  defp get_cache_dir do
    Application.get_env(:llm_db, :azure_foundry_cache_dir, @default_cache_dir)
  end

  defp write_cache(cache_path, manifest_path, content) do
    File.mkdir_p!(Path.dirname(cache_path))
    File.write!(cache_path, content)

    manifest = %{
      source_url: @api_url,
      sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
      size_bytes: byte_size(content),
      downloaded_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(manifest_path, Jason.encode!(manifest, pretty: true))
  end
end
