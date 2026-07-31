if is_nil(LLMDB.Store.snapshot()) do
  {:ok, _snapshot} = LLMDB.load()
end

ExUnit.start(capture_log: true, exclude: [:external])
