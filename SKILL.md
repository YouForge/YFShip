---
name: yfship
description: Operate the installed yfship CLI to compare one shipment or benchmark shipping rates from configured Chit Chats and Stallion providers on macOS.
---

# Operate YFShip

Use `yfship compare` for one destination and `yfship benchmark` for separate
provider averages across the canonical 63-destination Canada/United States
population. Prefer `--json` for agent workflows. Consult `yfship --help` and
the relevant subcommand help when syntax may have changed.

Do not invoke a provider unless the user has configured its credentials and
origin. Never print or relay credential values. Runs contact live provider APIs
and Chit Chats creates then deletes a temporary unpaid shipment while obtaining
rates.

## Inputs

Both commands require package weight in pounds through `--weight-lb`, package
dimensions in inches through `--length-in`, `--width-in`, and `--height-in`,
plus `--item-description`, `--item-value-cad`, and
`--item-origin-country`. Values for weight, dimensions, quantity, and item value
must be positive. `--quantity` defaults to `1`; `--hs-code` and `--sku` are
optional.

`compare` additionally requires `--to-address1`, `--to-city`, `--to-region`,
`--to-postal-code`, and `--to-country`. Add `--to-address2` when needed and
`--to-residential` for a residential destination.

Omitting `--provider` uses every configured provider. Repeat
`--provider chitchats` or `--provider stallion` to restrict the run. An
explicitly requested unconfigured provider is a setup failure.

## Read JSON results

All result documents have `schemaVersion: 1`, `command`, and `status`. Money is
encoded as a decimal string.

For `compare`, read top-level `selectedRate` as the cross-provider winner. Each
provider has `status`, all evaluated `rates`, its own `selectedRate`, and
optional `warning` or `error`. A rate is selectable only when `eligible` is
true. `ineligibilityReasons` explains rejected services. Top-level statuses are
`success`, `partial_success`, `no_eligible_option`, and
`complete_provider_failure`.

For `benchmark`, inspect each provider's `average`,
`qualifyingDestinationCount`, `failedDestinationCount`,
`noEligibleDestinationCount`, and `destinations`. Destination statuses are
`success`, `no_eligible`, or `failed`. `warningCount` reports Chit Chats cleanup
warnings; a nonzero value means rates may remain usable, but temporary shipment
cleanup needs attention. There is no blended cross-provider benchmark winner.

## Exit codes

| Exit | Interpretation |
| ---: | --- |
| `0` | Successful result. |
| `3` | Configuration or setup failure. |
| `4` | Compare found no eligible shipping option. |
| `5` | All provider work failed, or benchmark produced no usable provider average. |
| `6` | A usable result exists alongside a provider/destination failure. Parse the output. |
| `64` | Invalid command, missing option, or input-validation error. |

Treat exit `6` as usable but incomplete, not as an empty result. On exit `4`,
inspect provider rates and their `ineligibilityReasons`. On exit `5`, inspect
safe provider error codes/messages and retry only after addressing the cause.
Configuration and usage errors occur before a JSON result is emitted.

## Examples

Benchmark all configured providers:

```bash
yfship benchmark \
  --weight-lb 0.5 \
  --length-in 6 \
  --width-in 4 \
  --height-in 1 \
  --item-description "Synthetic accessory" \
  --item-value-cad 20.00 \
  --item-origin-country CA \
  --json
```

Benchmark only Stallion:

```bash
yfship benchmark \
  --weight-lb 1.25 \
  --length-in 8 \
  --width-in 5 \
  --height-in 2 \
  --item-description "Synthetic component" \
  --item-value-cad 35.00 \
  --item-origin-country CA \
  --provider stallion \
  --json
```

Compare a residential shipment with both configured providers:

```bash
yfship compare \
  --to-address1 "200 Synthetic St" \
  --to-city "Los Angeles" \
  --to-region CA \
  --to-postal-code 90012 \
  --to-country US \
  --to-residential \
  --weight-lb 0.5 \
  --length-in 6 \
  --width-in 4 \
  --height-in 1 \
  --item-description "Synthetic accessory" \
  --item-value-cad 20.00 \
  --item-origin-country CA \
  --provider chitchats \
  --provider stallion \
  --json
```

Compare with optional customs metadata:

```bash
yfship compare \
  --to-address1 "100 Synthetic Ave" \
  --to-city Toronto \
  --to-region ON \
  --to-postal-code "A1A 1A1" \
  --to-country CA \
  --weight-lb 0.75 \
  --length-in 7 \
  --width-in 5 \
  --height-in 2 \
  --item-description "Synthetic bracket" \
  --item-value-cad 18.50 \
  --item-origin-country CA \
  --quantity 2 \
  --hs-code 0000.00 \
  --sku SYNTH-001 \
  --json
```
