local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HyperLogLog = require(ReplicatedStorage:WaitForChild("HyperLogLog")) :: any

local function fuzzyEq(x: number, y: number, epsilon: number)
	return math.abs(x - y) <= epsilon
end

local tests = {

	["New Instance"] = function()
		-- Test default precision
		local hll_default = HyperLogLog.new()
		assert(hll_default.p == 14, "Default precision (p) should be 14")
		assert(hll_default.m == 2 ^ 14, "Default register count (m) should be 2^14")
		assert(buffer.len(hll_default.buffer) == 2 ^ 14 + 5, "Registers size should match m + 5")

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

	["Add and Estimate (Basic)"] = function()
		local hll = HyperLogLog.new(14)
		hll:add("a")
		hll:add("b")
		hll:add("c")

		local estimate = hll:estimate()
		assert(estimate == 3, "Estimate should be 3 for 3 unique items")

		-- Add duplicates
		hll:add("a")
		hll:add("b")
		hll:add("c")

		local estimate_after_dupes = hll:estimate()
		assert(estimate_after_dupes == 3, "Estimate should not change after adding duplicates")
	end,

	["Add and Estimate (Large)"] = function()
		local p = 10 -- Use lower precision for a faster test
		local hll = HyperLogLog.new(p)
		local count = 10000

		for i = 1, count do
			hll:add("item" .. i)
		end

		local estimate = hll:estimate()

		-- Standard error for HLL is ~1.04 / sqrt(m)
		-- For p=10, m=1024. Error ~1.04 / 32 = 0.0325 (3.25%)
		-- We'll use a 5% margin to be safe from test flakes.
		local error_margin = count * 0.05
		local diff = math.abs(estimate - count)

		assert(diff <= error_margin, `Estimate ${estimate} is not within 5% margin of ${count} (diff: ${diff})`)
	end,

	["Add (Non-string)"] = function()
		local hll = HyperLogLog.new(10)
		hll:add(123)
		hll:add(true)
		hll:add(Vector3.new(1, 2, 3))

		-- Create a table and get its string representation
		local t = { a = 1 }
		hll:add(t)

		local estimate = hll:estimate()
		assert(estimate == 4, `Estimate should be 4, got ${estimate}`)

		-- Add duplicates of non-string types
		hll:add(123)
		hll:add(Vector3.new(1, 2, 3))

		local estimate_after_dupes = hll:estimate()
		assert(estimate_after_dupes == 4, "Estimate should not change after adding non-string duplicates")
	end,

	["Merge (Basic)"] = function()
		local hll1 = HyperLogLog.new(12)
		hll1:add("a")
		hll1:add("b")
		hll1:add("c") -- common

		local hll2 = HyperLogLog.new(12)
		hll2:add("c") -- common
		hll2:add("d")
		hll2:add("e")

		local est1_before = hll1:estimate()
		local est2_before = hll2:estimate()

		assert(est1_before == 3, `hll1 estimate before merge should be 3, got ${est1_before}`)
		assert(est2_before == 3, `hll2 estimate before merge should be 3, got ${est2_before}`)

		hll1:merge(hll2)

		local est1_after = hll1:estimate()
		local est2_after = hll2:estimate() -- hll2 should be unchanged

		-- Total unique items: a, b, c, d, e (5)
		assert(fuzzyEq(est1_after, 5, 1), `hll1 estimate after merge should be 5, got ${est1_after}`)
		assert(fuzzyEq(est2_after, 3, 0), `hll2 estimate should be unchanged after merge, got ${est2_after}`)
	end,

	["Merge (Different Precision)"] = function()
		local hll1 = HyperLogLog.new(10)
		hll1:add("a")
		local est1_before = hll1:estimate()

		-- Convert registers to a string to check for changes
		local regs1_before = buffer.tostring(hll1.buffer)

		local hll2 = HyperLogLog.new(12)
		hll2:add("b")
		hll2:add("c")

		-- This should warn and not merge
		hll1:merge(hll2)

		local est1_after = hll1:estimate()
		local regs1_after = buffer.tostring(hll1.buffer)

		assert(est1_before == est1_after, "Estimate should not change after failed merge (different p)")
		assert(regs1_before == regs1_after, "Registers should not change after failed merge (different p)")
	end,

	["Serialize and Deserialize"] = function()
		local hll = HyperLogLog.new(8) -- Use p=8 for a small buffer
		hll:add("foo")
		hll:add("bar")
		hll:add(12345)

		local estimate_before = hll:estimate()

		local data = hll:serialize()
		assert(type(data) == "buffer", "serialize() should return a buffer")
		-- 1 byte for 'p' + 2^8 (256) bytes for registers
		assert(buffer.len(data) == 5 + 2 ^ 8, `Buffer length should be ${5 + 2 ^ 8}, got ${buffer.len(data)}`)

		local hll_deserialized = HyperLogLog.deserialize(data)

		assert(hll_deserialized, "deserialize() should return a new HLL object")
		assert(hll_deserialized.p == hll.p, "Deserialized HLL should have same precision (p)")
		assert(hll_deserialized.m == hll.m, "Deserialized HLL should have same register count (m)")

		local estimate_after = hll_deserialized:estimate()

		assert(
			estimate_before == estimate_after,
			`Estimates should match: before=${estimate_before}, after=${estimate_after}`
		)

		-- Verify registers are identical
		for i = 1, hll.m do
			assert(hll.buffer == hll_deserialized.buffer, `Register ${i} does not match`)
		end
	end,

	["Deserialize (Invalid Data)"] = function()
		-- Test with nil
		local hll_nil = HyperLogLog.deserialize(nil)
		assert(hll_nil == nil, "deserialize(nil) should return nil")

		-- Test with wrong type
		local hll_string = HyperLogLog.deserialize("not a buffer")
		assert(hll_string == nil, "deserialize(string) should return nil")

		-- Test with invalid buffer length
		-- p=10 (read from byte 0) means m=1024. Expected length = 1 + 1024 = 1025
		-- This buffer has p=10 but length=100
		local short_buffer = buffer.create(100)
		buffer.writeu8(short_buffer, 0, 10) -- Write p=10

		local hll_short = HyperLogLog.deserialize(short_buffer)
		assert(hll_short == nil, "deserialize(short buffer) should return nil")
	end,

	["Small Range Correction"] = function()
		-- With p=14 (m=16384), 2.5 * m = 40960
		-- Adding a few items should trigger the small range correction
		local hll = HyperLogLog.new(14)
		hll:add("item1")
		hll:add("item2")

		-- Check that there are zero registers
		local zero_registers = 0
		for i = 1, hll.m do
			if buffer.readu8(hll.buffer, i) == 0 then
				zero_registers += 1
			end
		end
		assert(zero_registers > 0, "There should be zero registers for small range correction")

		local estimate = hll:estimate()
		assert(estimate == 2, `Estimate should be 2, got ${estimate}`)
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
	local ok, err = pcall(f)
	testsList[i] = { ok, if ok then `✅ {name}` else `❌ {name}: {err}` }
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
