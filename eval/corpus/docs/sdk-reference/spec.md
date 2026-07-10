# Task: Write the API reference for an SDK class

Write the **API reference documentation** for a small client class from a
JavaScript SDK, **`KVStore`** — a typed wrapper over a key-value cache.
The audience is a developer using the SDK; they will read this reference
to call the class correctly.

Below is the source of truth: the class with its TypeScript signatures
and doc-comment-worthy behavior. Document the **public surface**; ignore
private members.

## Source of truth

```ts
interface KVStoreOptions {
  namespace: string;         // required; prefixes every key
  defaultTtlMs?: number;     // default TTL for set(); 0 or omitted = no expiry
  maxValueBytes?: number;    // reject values larger than this; default 1 MiB
}

class KVStore {
  constructor(options: KVStoreOptions);

  /** Store a value. Overwrites any existing value for `key`.
   *  `ttlMs` overrides the store's defaultTtlMs for this key.
   *  Throws RangeError if the serialized value exceeds maxValueBytes.
   *  Values are JSON-serialized; passing a non-JSON-serializable value
   *  (e.g. a function, a BigInt) throws TypeError. */
  async set<T>(key: string, value: T, ttlMs?: number): Promise<void>;

  /** Return the value for `key`, or `undefined` if absent or expired.
   *  The generic T is unchecked at runtime — you assert the shape. */
  async get<T>(key: string): Promise<T | undefined>;

  /** Return true if the key exists and is not expired. */
  async has(key: string): Promise<boolean>;

  /** Delete `key`. Returns true if a value was removed, false if the key
   *  was already absent. */
  async delete(key: string): Promise<boolean>;

  /** Get the value if present, else compute it with `factory`, store it
   *  (honoring `ttlMs`), and return it. `factory` runs at most once per
   *  concurrent miss (in-flight calls for the same key are coalesced). */
  async getOrSet<T>(key: string, factory: () => Promise<T>, ttlMs?: number): Promise<T>;

  /** Remove every key in this store's namespace. Does not affect other
   *  namespaces sharing the backend. */
  async clear(): Promise<void>;
}
```

## Requirements

Produce a single Markdown document, `reference.md`, covering:

- A short intro: what `KVStore` is and when to use it.
- **Construction**: the `KVStoreOptions` fields with types, required vs
  optional, defaults, and meaning (note the `defaultTtlMs = 0/omitted`
  ⇒ no-expiry rule and the `maxValueBytes` default).
- **Methods**: each public method with its signature, parameters, return
  value, and the error/edge behavior stated in the source (throws,
  return semantics of `delete`/`has`, expiry returning `undefined`, the
  coalescing behavior of `getOrSet`).
- At least one **realistic usage example** that shows `set`/`get` and the
  `getOrSet` cache-aside pattern.
- Call out the **runtime-unchecked generic** caveat on `get`/`getOrSet`.

## Constraints

- Document only what the source of truth specifies. Do not invent methods,
  options, or behaviors; do not omit documented ones.
- Example code must be **valid** against the shown signatures.

## Deliverable

A single `reference.md`.
