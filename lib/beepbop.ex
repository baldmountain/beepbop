defmodule BeepBop do
  @moduledoc """
  Manages the state machine of an `Ecto.Schema`.
  """

  alias Ecto.Multi
  alias BeepBop.{Utils, Context}

  @doc """
  Configures `BeepBop` to work with your `Ecto.Repo`.

  Expected keyword arguments:
  * `:ecto_repo` -- Since BeepBop does the routine persisting of "state", it
    needs to know which `Ecto.Repo` to use.
  """
  defmacro __using__(opts) do
    Utils.assert_repo!(opts)

    quote location: :keep do
      import BeepBop
      alias Ecto.Multi

      def __beepbop__(:repo), do: Keyword.fetch!(unquote(opts), :ecto_repo)

      Module.register_attribute(__MODULE__, :from_states, accumulate: true)
      Module.register_attribute(__MODULE__, :to_states, accumulate: true)
      Module.register_attribute(__MODULE__, :event_names, accumulate: true)

      @before_compile BeepBop
    end
  end

  defmacro state_machine(schema, column, states, do: block) do
    name = Utils.extract_schema_name(schema, __CALLER__)

    {states_list, _} = Code.eval_quoted(states)

    Utils.assert_states!(states_list)
    Utils.assert_num_states!(states_list)
    Module.put_attribute(__CALLER__.module, :beepbop_states, states_list)

    quote location: :keep,
          bind_quoted: [
            name: name,
            schema: schema,
            column: column,
            states: states,
            block: block
          ] do
      Module.eval_quoted(__MODULE__, [
        metadata(name, schema, column),
        context_validator(schema),
        persist_helpers()
      ])

      Utils.assert_schema!(schema, column)
      Utils.assert_states!(states)

      @doc """
      Returns the list of defined states in this machine.
      """
      @spec states :: [atom]
      def states do
        @beepbop_states
      end

      @doc """
      Checks if given `state` is defined in this machine.
      """
      @spec state_defined?(atom) :: boolean
      def state_defined?(state) do
        Enum.member?(@beepbop_states, state)
      end

      block
    end
  end

  defmacro event(event, options, callback) do
    quote location: :keep do
      transition_opts = unquote(options)

      Utils.assert_transition_opts!(transition_opts)

      event_from_states =
        case transition_opts do
          %{from: %{not: not_from}} ->
            Enum.reject(@beepbop_states, fn x -> x in not_from end)

          %{from: :any} ->
            @beepbop_states

          %{from: from} ->
            from
        end

      to_state = Map.get(transition_opts, :to)

      @from_states {unquote(event), event_from_states}
      @to_states {unquote(event), to_state}
      @event_names unquote(event)

      @doc """
      Runs the defined callback for this event.

      This function was generated by the `BeepBop.event/3` macro.
      """
      @spec unquote(event)(Context.t(), keyword) :: Context.t()
      def unquote(event)(context, opts \\ [persist: true])

      def unquote(event)(%Context{} = context, opts) do
        to_state = Map.get(unquote(options), :to)

        if can_transition?(context, unquote(event)) do
          context
          |> unquote(callback).()
          |> __beepbop_try_persist(to_state, opts)
        else
          struct(context, errors: {:error, "cannot transition, bad context"}, valid?: false)
        end
      end
    end
  end

  def metadata(name, schema, column) do
    quote location: :keep,
          bind_quoted: [
            name: name,
            module: schema,
            column: column
          ] do
      @beepbop_name name
      @beepbop_module module
      @beepbop_column column

      def __beepbop__(:name), do: @beepbop_name
      def __beepbop__(:module), do: @beepbop_module
      def __beepbop__(:column), do: @beepbop_column
      def __beepbop__(:states), do: @beepbop_states
    end
  end

  def context_validator(schema) do
    quote location: :keep do
      @doc """
      Validates the `context` struct.

      Returns `true` if `context` contains a struct of type `#{@beepbop_module}`
      under the `:struct` key.
      """
      @spec valid_context?(Context.t()) :: boolean
      def valid_context?(context)

      def valid_context?(%Context{
            struct: %unquote(schema){},
            valid?: true,
            state: s,
            multi: %Multi{}
          })
          when is_map(s),
          do: true

      def valid_context?(_), do: false
    end
  end

  def persist_helpers do
    quote location: :keep do
      defp __beepbop_final_multi(multi, struct, to_state) do
        Multi.run(multi, :persist, fn _repo, changes ->
          updated_struct = Map.get(changes, @beepbop_name) || struct
          to = Atom.to_string(to_state)
          __beepbop_persist(updated_struct, to)
        end)
      end

      defp __beepbop_try_persist(%Context{valid?: false} = context, _, _) do
        context
      end

      defp __beepbop_try_persist(%Context{valid?: true} = context, to_state, opts) do
        %{struct: struct, multi: multi} = context

        final_multi =
          case to_state do
            nil ->
              multi

            _ ->
              __beepbop_final_multi(multi, struct, to_state)
          end

        persist? = Keyword.get(opts, :persist, true)

        if persist? do
          repo = __beepbop__(:repo)
          repo_opts = Keyword.get(opts, :repo_opts, [])

          case repo.transaction(final_multi, repo_opts) do
            {:ok, result} ->
              struct(context, multi: result)

            error ->
              struct(context, valid?: false, errors: error)
          end
        else
          struct(context, multi: final_multi)
        end
      end
    end
  end

  def persistor(module) do
    if Module.defines?(module, {:persist, 2}, :def) do
      quote location: :keep do
        defp __beepbop_persist(struct, to_state) do
          __MODULE__.persist(struct, to_state)
        end
      end
    else
      quote location: :keep do
        defp __beepbop_persist(struct, to_state) do
          {:ok, Map.put(struct, @beepbop_column, to_state)}
        end
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    events = Module.get_attribute(env.module, :event_names)
    from_states = Module.get_attribute(env.module, :from_states)
    to_states = Module.get_attribute(env.module, :to_states)
    states = Module.get_attribute(env.module, :beepbop_states)

    Utils.assert_unique_events!(events)

    transitions =
      for event <- events, into: %{} do
        {event,
         %{
           from: Keyword.fetch!(from_states, event),
           to: Keyword.fetch!(to_states, event)
         }}
      end

    Utils.assert_transitions!(states, transitions)
    Module.put_attribute(env.module, :transitions, transitions)

    quote location: :keep do
      Module.eval_quoted(__MODULE__, persistor(__MODULE__))

      def __beepbop__(:events), do: @event_names
      def __beepbop__(:transitions), do: @transitions

      @doc """
      Validates the `context` struct and checks if the transition via `event` is
      valid.
      """
      @spec can_transition?(Context.t(), atom) :: boolean
      def can_transition?(context, event) do
        if valid_context?(context) do
          state =
            case Map.fetch(context.struct, @beepbop_column) do
              :error ->
                nil

              {:ok, something} when is_binary(something) ->
                String.to_atom(something)

              {:ok, something} when is_atom(something) ->
                something

              {:ok, nil} ->
                nil
            end

          from_states = Keyword.fetch!(@from_states, event)
          state in from_states
        else
          false
        end
      end
    end
  end
end
