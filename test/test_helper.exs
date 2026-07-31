{:ok, _snapshot} = LLMDB.load()

ExUnit.start(capture_log: true, exclude: [:external])
