# YFShip

YFShip is a Swift command-line tool for comparing all-in shipping rates from
Chit Chats and Stallion Express. It has two workflows:

- `benchmark` calculates a separate average for each provider across the
  canonical 63-destination Canada and United States benchmark.
- `compare` finds the cheapest eligible service for one shipment across the
  requested configured providers.

An eligible service must be trackable, have a proven delivery estimate of no
more than 20 business days, and provide a CAD-comparable all-in total. YFShip
v1 supports macOS 13 or newer only.

## Build and install

The package requires a Swift 6.3-compatible toolchain.

```bash
git clone https://github.com/YouForge/YFShip.git
cd YFShip
swift build
swift test
Scripts/install.sh
```

The installer builds in release mode and installs a standalone executable at
`~/.local/bin/yfship`. It does not use `sudo`.

If `~/.local/bin` is not already on your `PATH`, add it before invoking
`yfship` by name.

For the default macOS `zsh` shell:

```bash
touch ~/.zprofile
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.zprofile ||
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
exec zsh -l
command -v yfship
yfship --help
```

For `bash`:

```bash
touch ~/.bash_profile
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.bash_profile ||
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bash_profile
exec bash -l
command -v yfship
yfship --help
```

To use a different user-writable installation directory:

```bash
YFSHIP_INSTALL_DIR="$HOME/bin" Scripts/install.sh
```

Uninstall the command with the same directory setting used for installation:

```bash
Scripts/uninstall.sh
YFSHIP_INSTALL_DIR="$HOME/bin" Scripts/uninstall.sh
```

Uninstalling never removes user configuration.

## Configuration

YFShip reads configuration with this precedence, from highest to lowest:

1. Process environment variables.
2. `./.env` in the current working directory.
3. `~/.config/yfship/.env` for installed use.

For development inside the clone:

```bash
cp .env.example .env
```

For persistent configuration when invoking `yfship` from any directory:

```bash
mkdir -p ~/.config/yfship
cp .env.example ~/.config/yfship/.env
```

Fill in the five required origin fields:

```bash
YFSHIP_ORIGIN_ADDRESS1=100 Synthetic Ave
YFSHIP_ORIGIN_CITY=Hamilton
YFSHIP_ORIGIN_REGION_CODE=ON
YFSHIP_ORIGIN_POSTAL_CODE=A1A 1A1
YFSHIP_ORIGIN_COUNTRY_CODE=CA
```

`YFSHIP_ORIGIN_NAME`, `YFSHIP_ORIGIN_COMPANY`, `YFSHIP_ORIGIN_ADDRESS2`,
`YFSHIP_ORIGIN_EMAIL`, and `YFSHIP_ORIGIN_PHONE` are optional.
`YFSHIP_ORIGIN_RESIDENTIAL` accepts `true` or `false` and defaults to `false`.

Configure at least one provider. A partially configured provider is an error.

```bash
# Chit Chats
CHITCHATS_CLIENT_ID=
CHITCHATS_ACCESS_TOKEN=
CHITCHATS_PACKAGE_TYPE=

# Stallion Express
STALLION_ACCESS_TOKEN=
```

Keep both `.env` files private. The repository ignores `.env`, and errors do
not echo credential values.

## Commands

Runtime help is the canonical syntax reference:

```bash
yfship --help
yfship benchmark --help
yfship compare --help
```

Benchmark a synthetic package with all configured providers:

```bash
yfship benchmark \
  --weight-lb 0.5 \
  --length-in 6 \
  --width-in 4 \
  --height-in 1 \
  --item-description "Synthetic accessory" \
  --item-value-cad 20.00 \
  --item-origin-country CA
```

Compare one synthetic shipment and request stable JSON:

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
  --json
```

Repeat `--provider` to limit a run to specific configured providers, for
example by adding `--provider chitchats --provider stallion` to either complete
invocation above.

Money values in JSON are decimal strings. Every top-level JSON document has
`"schemaVersion": 1`; scripts should inspect `status`, provider results, and
`selectedRate` rather than parsing human output.

`--hs-code` is optional at the CLI level, but a valid product HS/customs code
is required for U.S.-bound shipments. Omitting it when the destination
country is `US` causes provider validation to fail for `compare`, and the
canonical `benchmark` population includes U.S. destinations, so the same
requirement applies there too.

## Errors and exit codes

Common setup errors identify missing configuration key names or an explicitly
requested provider that is not configured. Authentication and provider errors
are reported with safe categories. A provider failure does not discard a
usable result from another provider, and a compare run with no qualifying rate
reports an explicit no-eligible result.

| Exit | Meaning |
| ---: | --- |
| `0` | Success. |
| `3` | Configuration or setup failure. |
| `4` | Compare completed but no eligible shipping option exists. |
| `5` | Complete provider/API failure, including a benchmark with no usable provider average. |
| `6` | A usable result alongside a provider/destination failure or unusable benchmark provider result. |
| `64` | ArgumentParser usage or input-validation error. |

Exit `6` still includes usable human or JSON output. Configuration failures
occur before result output and are written to standard error.

## Project guidance

See [AGENTS.md](AGENTS.md) when changing the code and [SKILL.md](SKILL.md) when
operating the installed CLI from an agent.

YFShip is available under the MIT License. Copyright (c) 2026 potCat
Incorporated. See [LICENSE](LICENSE).
