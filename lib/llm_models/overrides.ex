defmodule LLMModels.Overrides do
  @moduledoc """
  Behaviour for providing runtime overrides to the LLM models catalog.

  Applications can implement this behaviour to customize providers, models,
  and exclusions without modifying configuration files.

  ## Usage

      defmodule MyApp.LlmModelOverrides do
        use LLMModels.Overrides

        @impl true
        def providers do
          [%{id: :openai, env: ["OPENAI_API_KEY"]}]
        end

        @impl true
        def models do
          [
            %{id: "gpt-4o-mini", provider: :openai,
              capabilities: %{tools: %{enabled: true, streaming: false}}}
          ]
        end

        @impl true
        def excludes do
          %{openai: ["gpt-5-pro"]}
        end
      end

  Then configure:

      config :llm_models, overrides_module: MyApp.LlmModelOverrides
  """

  @doc """
  Returns a list of provider override maps.

  Each map should conform to the Provider schema and will be merged with
  packaged provider data according to precedence rules.
  """
  @callback providers() :: [map()]

  @doc """
  Returns a list of model override maps.

  Each map should conform to the Model schema and will be merged with
  packaged model data according to precedence rules.
  """
  @callback models() :: [map()]

  @doc """
  Returns a map of exclusion patterns by provider.

  Format: `%{provider_atom => [pattern_strings]}`

  Patterns support glob syntax with `*` wildcards.

  ## Examples

      %{openai: ["gpt-5-pro", "o3-*"]}
  """
  @callback excludes() :: map()

  defmacro __using__(_opts) do
    quote do
      @behaviour LLMModels.Overrides
      @impl true
      def providers, do: []
      @impl true
      def models, do: []
      @impl true
      def excludes, do: %{}
      defoverridable providers: 0, models: 0, excludes: 0
    end
  end
end
