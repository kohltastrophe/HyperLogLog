--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HyperLogLog = require(ReplicatedStorage:WaitForChild("HyperLogLog")) :: any

local tests = {

	["New Instance"] = function()
		-- Test default precision
		local hll_default = HyperLogLog.new()
		assert(hll_default.p == 14, "Default precision (p) should be 14")
		assert(hll_default.m == 2 ^ 14, "Default register count (m) should be 2^14")

		-- NEW: Check for Lazy Allocation / Sparse Mode
		assert(hll_default.is_sparse == true, "New HLL should initialize in Sparse Mode")
		assert(hll_default.buffer == nil, "New HLL should not allocate a buffer immediately")
		assert(hll_default.sparse_count == 0, "Sparse count should initialize to 0")

		-- Test custom precision
		local hll_custom = HyperLogLog.new(10)
		assert(hll_custom.p == 10, "Custom precision (p) should be 10")
		assert(hll_custom.m == 2 ^ 10, "Custom register count (m) should be 2^10")

		-- Test precision clamping (min 4)
		local hll_low = HyperLogLog.new(2)
		assert(hll_low.p == 4, "Precision should be clamped to a min of 4")

		-- Test precision clamping (max 18)
		local hll_high = HyperLogLog.new(20)
		assert(hll_high.p == 18, "Precision should be clamped to a max of 18")
	end,

	["Add and Estimate (Sparse/Basic)"] = function()
		local hll = HyperLogLog.new(14)
		-- Add a few items (well below dense threshold)
		hll:add(1)
		hll:add(2)
		hll:add(3)

		assert(hll.is_sparse, "HLL should remain sparse with few items")

		local estimate = hll:estimate()
		-- Sparse estimation uses Linear Counting, so it should be exact for small integers
		assert(estimate == 3, `Estimate should be exactly 3 for sparse mode, got {estimate}`)

		-- Add duplicates
		hll:add(1)
		hll:add(2)
		hll:add(3)

		local estimate_after_dupes = hll:estimate()
		assert(estimate_after_dupes == 3, "Estimate should not change after adding duplicates")
	end,

	["Sparse to Dense Transition"] = function()
		-- p=10 means m=1024 registers.
		-- Threshold is 0.25 * 1024 = 256 items.
		local hll = HyperLogLog.new(10)
		local count = 300

		assert(hll.is_sparse == true, "Should start sparse")

		-- Add items just up to the threshold (approx)
		-- We force distinct hash impacts by using integers
		for i = 1, count do
			hll:add(i)
		end

		-- At 300 unique items, we typically fill > 256 registers due to distribution
		-- However, HLL collisions might keep us slightly under, so we add enough cushion.

		assert(hll.is_sparse :: any == false, "HLL should have converted to Dense Mode after exceeding threshold")
		assert(hll.buffer ~= nil, "HLL should have a buffer allocated in Dense Mode")
		assert(hll.sparse_registers == nil, "Sparse registers should be nil in Dense Mode")

		local estimate = hll:estimate()
		-- Allow for standard error since we are now in dense mode (approx 3.25% for p=10)
		-- We use a wider margin (5%) here to prevent flakes on the transition boundary
		local margin = count * 0.05
		local diff = math.abs(estimate - count)
		assert(diff <= margin, `Estimate {estimate} is not within 5% margin of {count} (margin: {margin})`)
	end,

	["Add and Estimate (Large/Dense)"] = function()
		local hll = HyperLogLog.new(10)
		local count = 10000 -- Far exceeds threshold

		for i = 1, count do
			hll:add(i)
		end

		assert(hll.is_sparse == false, "Should be dense")

		local estimate = hll:estimate()

		-- Standard error for HLL is ~1.04 / sqrt(m)
		-- For p=10, m=1024. Error ~1.04 / 32 = 0.0325 (3.25%)
		local margin = count * 0.0325
		local diff = math.abs(estimate - count)

		assert(diff <= margin, `Estimate {estimate} is not within 3.25% of {count} (margin: {margin})`)
	end,

	["Merge (Sparse + Sparse)"] = function()
		local hll1 = HyperLogLog.new(12)
		hll1:add(1)
		hll1:add(2)

		local hll2 = HyperLogLog.new(12)
		hll2:add(2) -- overlap
		hll2:add(3)

		hll1:merge(hll2)

		assert(hll1.is_sparse, "Merged small HLLs should remain sparse")
		assert(hll1:estimate() == 3, "Merge should result in Union (1,2,3)")
	end,

	["Merge (Dense + Sparse)"] = function()
		local hll_dense = HyperLogLog.new(10)
		-- Force densification
		local dense_count = 500
		for i = 1, dense_count do
			hll_dense:add(i)
		end
		assert(not hll_dense.is_sparse, "Setup failed: hll_dense is not dense")

		local hll_sparse = HyperLogLog.new(10)
		hll_sparse:add(10000) -- A unique item

		hll_dense:merge(hll_sparse)

		assert(not hll_dense.is_sparse, "Dense HLL should remain dense after merge")

		-- Expected total is 501.
		-- We use a 5% error margin because 500 is a small-ish number for Dense estimation,
		-- so variance can be higher than the asymptotic 3.25%.
		local est = hll_dense:estimate()
		local expected = dense_count + 1
		local margin = expected * 0.05

		local diff = math.abs(est - expected)

		assert(diff <= margin, `Estimate {est} is not within 5% of {expected} (margin: {margin})`)
	end,

	["Serialize and Deserialize"] = function()
		local hll = HyperLogLog.new(8) -- p=8, m=256
		hll:add(buffer.fromstring("foo"))
		hll:add(123)

		assert(hll.is_sparse, "Should be sparse before serialize")

		local data = hll:serialize()

		assert(type(data) == "buffer", "serialize() should return a buffer")

		-- Even if sparse, serialize returns the Dense Format for DataStore compatibility
		-- Length = 1 byte (p) + 256 bytes (registers)
		assert(buffer.len(data) == 1 + 2 ^ 8, `Buffer length should be {1 + 2 ^ 8}, got {buffer.len(data)}`)

		-- Deserialize
		local hll_loaded = HyperLogLog.deserialize(data)
		assert(hll_loaded, "deserialize() should return a new HLL object")
		assert(hll_loaded.is_sparse == false, "Deserialized objects are always Dense")
		assert(hll_loaded:estimate() == 2, "Deserialized estimate should match original")
	end,

	["Deserialize (Invalid Data)"] = function()
		local hll_nil = HyperLogLog.deserialize(nil :: any)
		assert(hll_nil == nil, "deserialize(nil) should return nil")

		local hll_string = HyperLogLog.deserialize("not a buffer" :: any)
		assert(hll_string == nil, "deserialize(string) should return nil")

		-- Test with invalid buffer length
		local short_buffer = buffer.create(100)
		buffer.writeu8(short_buffer, 0, 10) -- Write p=10 (expects 1024+1 bytes)
		local hll_short = HyperLogLog.deserialize(short_buffer)
		assert(hll_short == nil, "deserialize(short buffer) should return nil")
	end,
}

local testsList = {}
for name, f in tests do
	table.insert(testsList, { name, f })
end

table.sort(testsList, function(a: any, b: any)
	return a[1] < b[1]
end)

local fail = false
for i, v in testsList do
	local name, f = unpack(v)
	local ok, err = pcall(f :: any)
	testsList[i] = { ok, if ok then `✅ {name}` else `❌ {name}: {err}` :: any }
	if not ok then
		fail = true
	end
end

print("HyperLogLog Test Results:")

for i, v in testsList do
	if v[1] then
		print(v[2])
	else
		warn(v[2])
	end
end

if fail then
	error("One or more HyperLogLog tests failed")
end

return "All HyperLogLog tests passed."
