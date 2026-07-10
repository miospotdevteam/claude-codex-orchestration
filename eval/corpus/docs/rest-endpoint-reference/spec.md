# Task: Document a REST endpoint

Write the **public API reference** for a single REST endpoint of a
payments service called **Ledgerly**. Your reference will live in
Ledgerly's developer docs and is read by external engineers integrating
the API.

Below is the source of truth for the endpoint: an Express route handler
and the relevant type definitions. Document the endpoint **as a
consumer sees it** — do not document the internal implementation.

## Source of truth

```ts
// POST /v1/payment-links
// Requires header: Authorization: Bearer <secret API key>

interface CreatePaymentLinkBody {
  amount: number;          // in minor units (cents); must be >= 50
  currency: string;        // ISO 4217, lowercase; one of: usd, eur, gbp
  description?: string;    // shown to the payer; max 200 chars
  reference?: string;      // your own idempotency-friendly reference; max 64 chars
  expiresInHours?: number; // 1..720; defaults to 24
  metadata?: Record<string, string>; // up to 20 keys; values max 500 chars
}

interface PaymentLink {
  id: string;              // "pl_" + 24 hex chars
  url: string;             // hosted checkout URL to share with the payer
  amount: number;
  currency: string;
  description: string | null;
  reference: string | null;
  status: "open" | "paid" | "expired" | "canceled";
  expiresAt: string;       // ISO 8601 UTC
  createdAt: string;       // ISO 8601 UTC
  metadata: Record<string, string>;
}

app.post("/v1/payment-links", requireApiKey, async (req, res) => {
  const b = req.body as CreatePaymentLinkBody;

  if (typeof b.amount !== "number" || !Number.isInteger(b.amount) || b.amount < 50) {
    return res.status(422).json({ error: { code: "invalid_amount",
      message: "amount must be an integer of at least 50 minor units" } });
  }
  if (!["usd", "eur", "gbp"].includes(b.currency)) {
    return res.status(422).json({ error: { code: "invalid_currency",
      message: "currency must be one of: usd, eur, gbp" } });
  }
  if (b.description && b.description.length > 200) {
    return res.status(422).json({ error: { code: "invalid_description",
      message: "description must be at most 200 characters" } });
  }
  const hours = b.expiresInHours ?? 24;
  if (hours < 1 || hours > 720) {
    return res.status(422).json({ error: { code: "invalid_expiry",
      message: "expiresInHours must be between 1 and 720" } });
  }
  // ... on success:
  return res.status(201).json(link); // link: PaymentLink
});

// requireApiKey responds 401 { error: { code: "unauthorized",
//   message: "missing or invalid API key" } } when the bearer key is absent/bad.
// A malformed JSON body yields 400 { error: { code: "invalid_json", ... } }.
// The service applies a rate limit of 100 requests/minute per key; over that
// it responds 429 { error: { code: "rate_limited", ... } } with a Retry-After header.
```

## Requirements

Produce a single Markdown document, `reference.md`, that a competent
external developer could integrate against without seeing the source. It
must cover:

- A one-line summary of what the endpoint does and its method + path.
- **Authentication** (how the bearer key is passed).
- **Request**: every field with type, required/optional, constraints,
  and defaults.
- **Response**: the success status and the response object's fields.
- **Errors**: the error response shape and the meaningful error codes /
  status codes, including auth, validation, and rate limiting.
- At least one realistic **example request and example response** (a
  `curl` example is appropriate; keys/values may be illustrative).

## Constraints

- Document only the observable contract. Do not invent fields, endpoints,
  or behaviors that are not in the source of truth, and do not omit ones
  that are.
- Values in examples may be illustrative but must be **consistent** with
  the documented constraints (e.g. a valid currency, an amount ≥ 50).

## Deliverable

A single `reference.md`.
