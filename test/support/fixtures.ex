defmodule LLMModels.Test.Fixtures do
  @moduledoc """
  Synthetic test data fixtures for LLM model testing.

  Uses generic, descriptive names to avoid coupling to real-world models
  and providers. All fixtures return maps that can be overridden with
  custom values via the `overrides` parameter.

  ## Provider Fixtures

  - `provider_alpha/1` - Basic test provider
  - `provider_beta/1` - Alternative test provider
  - `provider_gamma/1` - Third test provider

  ## Model Fixtures

  - `model_simple/1` - Minimal valid model
  - `model_basic/1` - Model with common fields
  - `model_full/1` - Model with complete metadata
  - `model_with_limits/1` - Model with token limits
  - `model_with_cost/1` - Model with pricing
  - `model_with_capabilities/1` - Model with various capabilities
  - `model_multimodal/1` - Model supporting multiple modalities
  - `model_deprecated/1` - Deprecated model
  - `model_with_special_chars/1` - Model ID with special characters
  - `model_with_custom_fields/1` - Model with unknown/custom fields
  - `model_with_family/2` - Model belonging to a family

  ## Usage

      # Use as-is
      provider = provider_alpha()
      
      # Override specific fields
      provider = provider_alpha(%{name: "Custom Name"})
      
      # Create model with family
      model = model_with_family("test-family-v1", %{id: "custom-id"})
  """

  @doc """
  Basic test provider (alpha).
  """
  def provider_alpha(overrides \\ %{}) do
    Map.merge(
      %{
        id: :test_provider_alpha,
        name: "Test Provider Alpha",
        url: "https://alpha.example.com"
      },
      overrides
    )
  end

  @doc """
  Alternative test provider (beta).
  """
  def provider_beta(overrides \\ %{}) do
    Map.merge(
      %{
        id: :test_provider_beta,
        name: "Test Provider Beta",
        url: "https://beta.example.com"
      },
      overrides
    )
  end

  @doc """
  Third test provider (gamma).
  """
  def provider_gamma(overrides \\ %{}) do
    Map.merge(
      %{
        id: :test_provider_gamma,
        name: "Test Provider Gamma",
        url: "https://gamma.example.com"
      },
      overrides
    )
  end

  @doc """
  Minimal valid model with only required fields.
  """
  def model_simple(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-simple",
        provider_id: :test_provider_alpha,
        name: "Test Model Simple"
      },
      overrides
    )
  end

  @doc """
  Basic model with common fields.
  """
  def model_basic(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-basic",
        provider_id: :test_provider_alpha,
        name: "Test Model Basic",
        description: "A basic test model for general testing",
        context_window: 8192,
        max_output_tokens: 4096
      },
      overrides
    )
  end

  @doc """
  Model with complete metadata including limits, cost, and capabilities.
  """
  def model_full(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-full",
        provider_id: :test_provider_alpha,
        name: "Test Model Full",
        description: "A fully-featured test model with complete metadata",
        context_window: 128_000,
        max_output_tokens: 16_384,
        supports_streaming: true,
        supports_tools: true,
        supports_vision: true,
        supports_audio: false,
        modalities: [:text, :image],
        input_cost_per_token: 0.000003,
        output_cost_per_token: 0.000015,
        release_date: ~D[2024-01-15],
        deprecated: false,
        family: "test-family"
      },
      overrides
    )
  end

  @doc """
  Model focused on token limits.
  """
  def model_with_limits(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-limits",
        provider_id: :test_provider_alpha,
        name: "Test Model With Limits",
        context_window: 32_768,
        max_output_tokens: 8192,
        max_tokens: 8192
      },
      overrides
    )
  end

  @doc """
  Model with pricing information.
  """
  def model_with_cost(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-cost",
        provider_id: :test_provider_beta,
        name: "Test Model With Cost",
        input_cost_per_token: 0.000001,
        output_cost_per_token: 0.000002,
        input_cost_per_image: 0.005,
        context_window: 16_384
      },
      overrides
    )
  end

  @doc """
  Model with various capability flags.
  """
  def model_with_capabilities(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-capabilities",
        provider_id: :test_provider_alpha,
        name: "Test Model With Capabilities",
        supports_streaming: true,
        supports_tools: true,
        supports_vision: true,
        supports_audio: true,
        supports_prompt_caching: true,
        context_window: 200_000
      },
      overrides
    )
  end

  @doc """
  Model supporting multiple modalities.
  """
  def model_multimodal(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-multimodal",
        provider_id: :test_provider_beta,
        name: "Test Model Multimodal",
        modalities: [:text, :image, :audio, :video],
        supports_vision: true,
        supports_audio: true,
        context_window: 100_000
      },
      overrides
    )
  end

  @doc """
  Deprecated model.
  """
  def model_deprecated(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-deprecated",
        provider_id: :test_provider_alpha,
        name: "Test Model Deprecated",
        deprecated: true,
        deprecation_date: ~D[2024-06-01],
        replacement_model: "test-model-basic",
        context_window: 4096
      },
      overrides
    )
  end

  @doc """
  Model with special characters in ID (colon, slash, @, dots).
  """
  def model_with_special_chars(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test:model/special@chars.v1.0",
        provider_id: :test_provider_gamma,
        name: "Test Model Special Chars",
        description: "Model with various special characters in ID",
        context_window: 8192
      },
      overrides
    )
  end

  @doc """
  Model with custom/unknown fields that should be preserved.
  """
  def model_with_custom_fields(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-custom",
        provider_id: :test_provider_alpha,
        name: "Test Model Custom Fields",
        context_window: 8192,
        custom_field_string: "custom_value",
        custom_field_number: 42,
        custom_field_list: ["a", "b", "c"],
        custom_field_map: %{nested: "data"},
        experimental_feature: true
      },
      overrides
    )
  end

  @doc """
  Model belonging to a specific family.

  ## Examples

      model_with_family("test-family-v1")
      model_with_family("test-family-v2", %{max_output_tokens: 8192})
  """
  def model_with_family(family_id, overrides \\ %{}) do
    Map.merge(
      %{
        id: "#{family_id}-model",
        provider_id: :test_provider_alpha,
        name: "Test Model #{family_id}",
        family: family_id,
        context_window: 16_384
      },
      overrides
    )
  end

  @doc """
  Returns a list of basic test models for bulk operations.
  """
  def models_basic_list do
    [
      model_simple(%{id: "test-model-1"}),
      model_simple(%{id: "test-model-2", provider_id: :test_provider_beta}),
      model_simple(%{id: "test-model-3", provider_id: :test_provider_gamma})
    ]
  end

  @doc """
  Returns a list of models with varying metadata completeness.
  """
  def models_varied_list do
    [
      model_simple(),
      model_basic(),
      model_full(),
      model_with_limits(),
      model_with_cost(),
      model_deprecated()
    ]
  end

  @doc """
  Returns a spec string for a test model.

  ## Examples

      spec(:test_provider_alpha, "test-model-1")
      # => "test_provider_alpha:test-model-1"
  """
  def spec(provider_id, model_id) when is_atom(provider_id) and is_binary(model_id) do
    "#{provider_id}:#{model_id}"
  end

  @doc """
  Returns a spec string from a model map.

  ## Examples

      spec_from_model(model_simple())
      # => "test_provider_alpha:test-model-simple"
  """
  def spec_from_model(%{provider_id: provider_id, id: model_id}) do
    spec(provider_id, model_id)
  end

  # Fixtures for enrichment testing (using `provider` field instead of `provider_id`)

  @doc """
  Model with derivable family from ID.
  """
  def model_with_derivable_family(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-v2-pro",
        provider: :test_provider_alpha
      },
      overrides
    )
  end

  @doc """
  Model with existing family that should be preserved.
  """
  def model_with_existing_family(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-v2-mini",
        provider: :test_provider_alpha,
        family: "custom-family"
      },
      overrides
    )
  end

  @doc """
  Model with single-segment ID (cannot derive family).
  """
  def model_single_segment(overrides \\ %{}) do
    Map.merge(
      %{
        id: "model",
        provider: :test_provider_alpha
      },
      overrides
    )
  end

  @doc """
  Model with complete metadata for enrichment.
  """
  def model_complete(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-model-v1-advanced",
        provider: :test_provider_alpha,
        name: "Test Model V1 Advanced",
        release_date: "2024-07-18",
        limits: %{context: 128_000},
        cost: %{input: 0.15, output: 0.60},
        capabilities: %{chat: true},
        tags: ["fast"],
        deprecated: false,
        aliases: ["mini"],
        extra: %{"custom" => "value"}
      },
      overrides
    )
  end

  @doc """
  Returns the expected family for a given model ID based on naming patterns.
  Uses similar logic to the actual derive_family function.
  """
  def expected_family_for_model(model_id) when is_binary(model_id) do
    segments = String.split(model_id, "-")

    case length(segments) do
      1 -> nil
      2 -> Enum.at(segments, 0)
      _ -> segments |> Enum.slice(0..-2//1) |> Enum.join("-")
    end
  end

  @doc """
  List of models for batch enrichment testing.
  """
  def models_for_enrichment do
    [
      %{id: "test-model-v1-mini", provider: :test_provider_alpha},
      %{id: "test-model-v2-pro", provider: :test_provider_beta},
      %{id: "test-model-v3-ultra", provider: :test_provider_gamma}
    ]
  end

  @doc """
  List of models with mixed completeness for enrichment.
  """
  def models_mixed_enrichment do
    [
      %{id: "test-model-v1", provider: :test_provider_alpha},
      %{id: "test-model-v2-pro", provider: :test_provider_beta, family: "custom"},
      %{
        id: "test-model-v3-flash",
        provider: :test_provider_gamma,
        provider_model_id: "test-model-v3-flash-002"
      }
    ]
  end

  @doc """
  List of models where family cannot be derived.
  """
  def models_no_derivable_family do
    [
      %{id: "model", provider: :test_provider_alpha},
      %{id: "another", provider: :test_provider_beta}
    ]
  end
end
