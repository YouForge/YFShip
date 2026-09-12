# YFShip contributor guide

YFShip is a macOS-only Swift 6 command-line application. Keep v1 small,
explicit, and SwiftPM-first. Run `swift build` and `swift test` before handing
off changes; the default test suite must remain fully offline.

## Architecture boundaries

The dependency direction is:

```text
CLI -> Services -> ShippingProvider -> provider adapter/client -> HTTPClient
                                      -> Foundation URLSession
```

- `CLI/` parses and validates user input, constructs runtime dependencies, and
  maps domain outcomes to process exits.
- `Configuration/` owns `.env` loading and provider/origin construction.
- `Domain/` contains provider-independent values only.
- `Networking/` owns the shared `HTTPClient` transport seam.
- `Providers/` owns API requests, external DTOs, and normalization into domain
  `ShippingRate` values. Provider DTOs must never escape this directory.
- `Services/` applies shared eligibility, comparison, and benchmark behavior.
- `Output/` renders domain results. Human output may evolve; JSON is a stable
  public interface.

Do not add protocols without a concrete testing or substitution need. The two
intentional seams are `HTTPClient` and `ShippingProvider`.
`ShippingProvider.ratesWithWarning` keeps a Chit Chats cleanup warning attached
to one request without shared mutable state; the default implementation wraps
ordinary `rates` results for providers that have no warning lifecycle.

## Locked business rules

- Tracking is mandatory. Both `false` and unknown tracking are ineligible.
- The delivery upper bound must be known and no greater than 20 business days.
  Provider ranges normalize to their upper bound; unknown estimates fail.
- Compare mandatory all-in totals as `Decimal`, never optional insurance,
  signature, or other add-ons.
- Only CAD-comparable rates are eligible. Currency comparison is
  case-insensitive; do not introduce silent numeric FX comparison.
- Select each provider's cheapest eligible service per destination, then the
  cheapest eligible service across providers for `compare`.
- Preserve partial provider failure and explicit no-eligible outcomes.
- The benchmark is an unweighted arithmetic mean. Every destination has weight
  `1.0`, and the denominator is the qualifying destination count, not 63.
- Benchmark requests use at most five destinations concurrently.
- A valid product HS/customs code (`--hs-code` / `ShipmentItem.hsCode`) is a
  provider/runtime requirement for U.S.-bound shipments, not a universally
  required `ArgumentParser` option. Omitting it for a U.S. destination causes
  provider validation failure in `compare`; the canonical benchmark
  population includes U.S. destinations, so the same requirement applies to
  `benchmark`. Do not make `--hs-code` required at the CLI level to work
  around this — it must stay optional for non-U.S. shipments.

## Benchmark resource

`Sources/YFShip/Resources/BenchmarkDestinations.json` is the reviewed runtime
source for 63 destinations: 12 Canada and 51 United States. SwiftPM embeds it
with `.embedInCode`; `BenchmarkDestinationLoader` decodes
`PackageResources.BenchmarkDestinations_json` from the executable.

Change the dataset deliberately: update the JSON source, revalidate changed
addresses against both providers, preserve unique IDs and weight `1.0`, and run
the resource tests for count, country split, uniqueness, weights, and required
address fields. Do not substitute historical or private customer addresses.

## Configuration and secrets

Configuration precedence is process environment, `./.env`, then
`~/.config/yfship/.env`. The parser intentionally supports only `KEY=value`,
blank lines, and full-line comments. Keep `.env` ignored and `.env.example`
synthetic and secret-free.

Never commit credentials, account/customer identifiers, private contact data,
raw authorization headers, or unsanitized production responses. Errors must
name safe categories and missing key names without echoing values or arbitrary
provider bodies.

## Tests and compatibility

Use Swift Testing (`import Testing`, `@Test`, and `#expect`). Provider tests use
`MockHTTPClient` plus minimal sanitized fixtures in
`Tests/YFShipTests/Fixtures/`; they must verify request shape and mapping without
network or account side effects. Chit Chats tests must cover temporary shipment
creation, rate decoding, best-effort DELETE, and cleanup-warning propagation.

JSON documents always include `schemaVersion: 1`. Money is encoded as POSIX
decimal strings, status and provider identifiers are stable lowercase values,
and nullability is covered by contract tests. Do not rename fields, change
their meaning, or omit currently explicit nulls silently. Make intentional
schema changes visible through versioning, tests, and operator documentation.

## Scope and providers

Do not add v1 non-goals such as label purchase, shipment management, caching,
databases, GUI/TUI, provider discovery, retry frameworks, FX services,
telemetry, generalized units/weighting, or Linux/Windows support promises.

To add a provider:

1. Add a lowercase `ProviderID` and provider-scoped configuration keys.
2. Add concrete client/DTO/adapter files under `Providers/<Provider>/`.
3. Authenticate and form requests in the client through `HTTPClient`.
4. Normalize mandatory all-in cost, currency, tracking, and ETA in the adapter.
5. Wire construction into `CommandRuntime` without leaking DTOs upward.
6. Add sanitized success/error/edge fixtures and fully offline adapter tests.
7. Extend engine, CLI selection, human output, and frozen JSON contract tests.
8. Update `.env.example`, runtime help when needed, README.md, and SKILL.md.

Use sparse comments that explain durable provider constraints, safety rules, or
non-obvious lifecycle/concurrency choices rather than narrating code.
