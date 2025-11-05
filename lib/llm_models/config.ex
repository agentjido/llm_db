defmodule LLMModels.Config do
  @moduledoc """
  Configuration reading and normalization for LLMModels.

  Reads from Application environment and provides normalized config maps,
  compiled filter patterns, and module-based overrides.
  """

  @doc """
  Returns normalized configuration map from Application environment.

  Reads `:llm_models` application config and normalizes with defaults.

  ## Returns

  A map with keys:
  - `:compile_embed` - Whether to compile-time embed snapshot (default: false)
  - `:overrides` - Map with `:providers`, `:models`, `:exclude` keys
  - `:overrides_module` - Module implementing LLMModels.Overrides behaviour (optional)
  - `:allow` - Allow patterns (`:all` or `%{provider => [patterns]}`)
  - `:deny` - Deny patterns (`%{provider => [patterns]}`)
  - `:prefer` - List of preferred provider atoms
  """
  @spec get() :: map()
  def get do
    config = Application.get_all_env(:llm_models)

    %{
      compile_embed: Keyword.get(config, :compile_embed, false),
      overrides: normalize_overrides(Keyword.get(config, :overrides, %{})),
      overrides_module: Keyword.get(config, :overrides_module),
      allow: Keyword.get(config, :allow, :all),
      deny: Keyword.get(config, :deny, %{}),
      prefer: Keyword.get(config, :prefer, [])
    }
  end

  @doc """
  Compiles allow/deny filter patterns to regexes for performance.

  ## Parameters

  - `allow` - `:all` or `%{provider_atom => [pattern_strings]}`
  - `deny` - `%{provider_atom => [pattern_strings]}`

  Patterns support glob syntax with `*` wildcards via `LLMModels.Merge.compile_pattern/1`.

  Deny patterns always win over allow patterns.

  ## Returns

  `%{allow: compiled_patterns, deny: compiled_patterns}`

  Where `compiled_patterns` is either `:all` or `%{provider => [%Regex{}]}`.
  """
  @spec compile_filters(allow :: :all | map(), deny :: map()) :: %{
          allow: :all | map(),
          deny: map()
        }
  def compile_filters(allow, deny) do
    %{
      allow: compile_patterns(allow),
      deny: compile_patterns(deny)
    }
  end

  @doc """
  Retrieves overrides from a module implementing LLMModels.Overrides behaviour.

  ## Parameters

  - `module_name` - Module atom or `nil`

  ## Returns

  `%{providers: [], models: [], excludes: %{}}`

  Returns empty values if module is `nil` or not found.
  """
  @spec get_overrides_from_module(module() | nil) :: %{
          providers: [map()],
          models: [map()],
          excludes: map()
        }
  def get_overrides_from_module(nil), do: %{providers: [], models: [], excludes: %{}}

  def get_overrides_from_module(module_name) when is_atom(module_name) do
    if Code.ensure_loaded?(module_name) do
      %{
        providers: module_name.providers(),
        models: module_name.models(),
        excludes: module_name.excludes()
      }
    else
      %{providers: [], models: [], excludes: %{}}
    end
  rescue
    _error ->
      %{providers: [], models: [], excludes: %{}}
  end

  # Private helpers

  defp normalize_overrides(overrides) when is_map(overrides) do
    %{
      providers: Map.get(overrides, :providers, []),
      models: Map.get(overrides, :models, []),
      exclude: Map.get(overrides, :exclude, %{})
    }
  end

  defp normalize_overrides(overrides) when is_list(overrides) do
    %{
      providers: Keyword.get(overrides, :providers, []),
      models: Keyword.get(overrides, :models, []),
      exclude: Keyword.get(overrides, :exclude, %{})
    }
  end

  defp normalize_overrides(_), do: %{providers: [], models: [], exclude: %{}}

  defp compile_patterns(:all), do: :all

  defp compile_patterns(patterns) when is_map(patterns) do
    Map.new(patterns, fn {provider, pattern_list} ->
      compiled = Enum.map(pattern_list, &LLMModels.Merge.compile_pattern/1)
      {provider, compiled}
    end)
  end

  defp compile_patterns(_), do: %{}
end
