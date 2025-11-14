## 💡 What is HyperLogLog?

HyperLogLog (HLL) is a probabilistic algorithm that allows you to estimate the number of unique items in a set (its "cardinality") using a very small, fixed amount of memory.

For example, you can use it to answer questions like:

- "How many **unique players** joined my game today?"
- "How many **unique votes** were cast in this poll?"
- "How many **unique items** were favorited this week?"

...all while using just a few kilobytes of memory, even if the number of items is in the millions or billions.

## 🤔 Why use HyperLogLog?

Counting unique items seems simple, but it can be very difficult at scale.

Imagine you want to count the unique players who join your game in a day. The "simple" way is to store every unique `UserId` in a table and check `#table` at the end. If you have 10,000 unique players, your table is small. If you have **10 million** unique players, that table becomes enormous, consuming vast amounts of memory.

> This is commonly known as the [count-distinct problem](https://en.wikipedia.org/wiki/Count-distinct_problem) in computer science.

HyperLogLog solves this problem by trading perfect accuracy for massive efficiency.

- **🚀 Extremely Fast:** Adding an item is just a quick hashing operation and a memory check. It's a constant-time operation $O(1)$ that doesn't slow down as the count grows.
- **💾 Incredibly Memory-Efficient:** This is the key benefit. A HyperLogLog counter uses a **small, fixed amount of memory** (just a few kilobytes) whether you add 1,000 items or 1,000,000,000 items.
- **🤝 Mergeable:** You can take two separate HLL counters (e.g., from different game servers) and merge them together. The resulting counter will give you the estimated unique count _across both sets_. This is extremely powerful for distributed data.
- **📈 Tunable Accuracy:** It's an estimate, but it's a very good one. You can control the accuracy vs. memory trade-off using the `precision` parameter. A higher precision gives you a more accurate estimate at the cost of more memory.

It's the perfect tool for when you need a "good enough" count of unique items at a massive scale, without sacrificing performance or memory.

## 🛠️ Installation

1.  Download [`init.luau`](src/init.luau) from the `src/` directory.
2.  Place the file into your project (e.g., `ServerStorage/Modules/HyperLogLog`).
3.  Require the module in your script:

```luau
local HyperLogLog = require(game.ServerStorage.Modules.HyperLogLog)
```

## 🚀 Quick Start

Here's a simple example of counting 1,000 unique items.

```luau
local HyperLogLog = require(game.ServerStorage.Modules.HyperLogLog)

-- Create a new HLL counter with precision 14 (default)
-- Higher precision = more accuracy, but more memory.
local counter = HyperLogLog.new(14)

-- Add 1,000 unique items to the counter
for i = 1, 1000 do
	counter:add(i)
end

-- Estimate the cardinality
local uniqueCount = counter:estimate()

-- The estimate will be very close to 1000
print("Estimated unique items: " .. uniqueCount)
```

## 📚 API Reference

### `HyperLogLog.new(precision)`

Creates a new, empty HyperLogLog counter.

- **`precision`** (number?): An integer between 4 and 18. This defines the accuracy and memory usage. It defaults to `14`.
  - Memory usage is $2^p$ (e.g., `p=14` uses $2^{14} = 16384$ 1 byte registers).
  - Standard error is $\approx 1.04 / \sqrt{2^p}$.
- **Returns**: (HyperLogLog): A new counter object.

---

### `HLL:add(item)`

Adds an item to the counter.

- **`item`** (buffer | number): The unique item identifier to add.

---

### `HLL:estimate()`

Calculates and returns the current estimated cardinality.

- **Returns**: (number): The estimated number of unique items added so far, rounded to the nearest integer.

---

### `HLL:merge(other)`

Merges another HLL counter into this one. This is useful for combining distributed or parallel counts.

> [!WARNING]
> Both counters **must** have been created with the same precision (`p`).

- **`other`** (HyperLogLog): The other counter to merge into this one. This operation modifies the current counter.

```luau
-- Count unique players on Server 1
local server1_uniques = HyperLogLog.new(14)
server1_uniques:add(1)
server1_uniques:add(2)

-- Count unique players on Server 2
local server2_uniques = HyperLogLog.new(14)
server2_uniques:add(2)
server2_uniques:add(3)

-- Merge Server 2's count into Server 1's
server1_uniques:merge(server2_uniques)

-- The estimate will now be ~3 (1, 2, 3)
print(server1_uniques:estimate())
```

---

### `HLL:serialize()`

Returns a serialized buffer containing the counter's state. This is useful for saving the counter in a `DataStore`.

- **Returns**: (buffer): A buffer with the `p` (precision) and `registers` (internal state).

```luau
local state = counter:serialize()
-- Now you can save 'state' to a DataStore
```

---

### `HyperLogLog.deserialize(data)`

Reloads a counter from a serialized buffer.

- **`data`** (buffer): A state buffer previously generated by `HLL:serialize()`.
- **Returns**: (HyperLogLog): A new counter object with the restored state.

```luau
-- 'savedState' is loaded from a DataStore
local counter = HyperLogLog.deserialize(savedState)

-- You can now continue adding items or estimating
counter:add(newUserId)
print(counter:estimate())
```

## Credits

Thanks to [@XoifailTheGod](https://www.roblox.com/users/558808710) for helping optimize and test the library.

## References

- https://research.google.com/pubs/archive/40671.pdf
- https://docs.google.com/document/d/1gyjfMHy43U9OWBXxfaeG-3MjGzejW1dlpyMwEYAAWEI/mobilebasic
