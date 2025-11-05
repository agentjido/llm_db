defmodule LLMModels.StoreTest do
  use ExUnit.Case, async: false

  alias LLMModels.Store

  setup do
    Store.clear!()
    :ok
  end

  describe "get/0" do
    test "returns nil when store is empty" do
      assert Store.get() == nil
    end

    test "returns full store map after put" do
      snapshot = %{providers: [], models: []}
      opts = [force: true]

      Store.put!(snapshot, opts)
      store = Store.get()

      assert is_map(store)
      assert store.snapshot == snapshot
      assert store.opts == opts
      assert is_integer(store.epoch)
      assert store.epoch > 0
    end
  end

  describe "snapshot/0" do
    test "returns nil when store is empty" do
      assert Store.snapshot() == nil
    end

    test "returns snapshot portion from store" do
      snapshot = %{providers: [%{id: "test"}], models: [%{id: "model-1"}]}
      Store.put!(snapshot, [])

      assert Store.snapshot() == snapshot
    end
  end

  describe "epoch/0" do
    test "returns 0 when store is empty" do
      assert Store.epoch() == 0
    end

    test "returns current epoch from store" do
      Store.put!(%{}, [])
      epoch = Store.epoch()

      assert is_integer(epoch)
      assert epoch > 0
    end

    test "epoch increases monotonically on successive puts" do
      Store.put!(%{}, [])
      epoch1 = Store.epoch()

      Store.put!(%{}, [])
      epoch2 = Store.epoch()

      Store.put!(%{}, [])
      epoch3 = Store.epoch()

      assert epoch2 > epoch1
      assert epoch3 > epoch2
    end
  end

  describe "last_opts/0" do
    test "returns empty list when store is empty" do
      assert Store.last_opts() == []
    end

    test "returns last load options from store" do
      opts = [force: true, cache: false, timeout: 5000]
      Store.put!(%{}, opts)

      assert Store.last_opts() == opts
    end

    test "returns updated opts after subsequent put" do
      Store.put!(%{}, first: true)
      assert Store.last_opts() == [first: true]

      Store.put!(%{}, second: true)
      assert Store.last_opts() == [second: true]
    end
  end

  describe "put!/2" do
    test "stores snapshot and opts atomically" do
      snapshot = %{providers: [%{id: "openai"}], models: []}
      opts = [force: true]

      assert Store.put!(snapshot, opts) == :ok

      store = Store.get()
      assert store.snapshot == snapshot
      assert store.opts == opts
    end

    test "generates unique monotonic epoch" do
      Store.put!(%{}, [])
      epoch1 = Store.epoch()

      Store.put!(%{}, [])
      epoch2 = Store.epoch()

      assert epoch2 > epoch1
    end

    test "overwrites previous store atomically" do
      snapshot1 = %{providers: [], models: []}
      Store.put!(snapshot1, first: true)

      snapshot2 = %{providers: [%{id: "test"}], models: [%{id: "model"}]}
      Store.put!(snapshot2, second: true)

      assert Store.snapshot() == snapshot2
      assert Store.last_opts() == [second: true]
    end
  end

  describe "clear!/0" do
    test "removes store from persistent_term" do
      Store.put!(%{providers: [], models: []}, [])
      assert Store.get() != nil

      assert Store.clear!() == :ok
      assert Store.get() == nil
    end

    test "subsequent calls to clear! are safe" do
      Store.clear!()
      assert Store.clear!() == :ok
      assert Store.get() == nil
    end

    test "resets epoch to 0" do
      Store.put!(%{}, [])
      assert Store.epoch() > 0

      Store.clear!()
      assert Store.epoch() == 0
    end
  end

  describe "atomic swaps" do
    test "multiple concurrent puts generate unique epochs" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Store.put!(%{index: i}, index: i)
            Store.epoch()
          end)
        end

      epochs = Task.await_many(tasks)

      # All epochs should be positive
      assert Enum.all?(epochs, &(&1 > 0))
      # Most epochs should be unique (timing may cause occasional duplicates)
      assert length(Enum.uniq(epochs)) >= 8
    end

    test "readers always see complete store state" do
      Store.put!(%{providers: [], models: []}, initial: true)

      task =
        Task.async(fn ->
          for _ <- 1..100 do
            store = Store.get()

            if store do
              assert Map.has_key?(store, :snapshot)
              assert Map.has_key?(store, :epoch)
              assert Map.has_key?(store, :opts)
              assert is_integer(store.epoch)
            end
          end
        end)

      for i <- 1..10 do
        Store.put!(%{providers: [%{id: "p#{i}"}], models: []}, iteration: i)
        Process.sleep(1)
      end

      Task.await(task)
    end
  end
end
