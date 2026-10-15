# tdp

A 1-to-10 TDP power slider for the **GPD WIN 5** (AMD Ryzen AI Max+ 395,
"Strix Halo") on Linux / NixOS. Think of it as the terminal equivalent of
GPD's Windows "Motion Assistant" TDP slider — but with the safe power
envelope for *this specific chassis* baked in.

```
$ tdp

  GPD WIN 5 · Strix Halo TDP ladder
  ──────────────────────────────────────────────────────────
     1   15W  battery / idle, whisper quiet      #
     2   25W  light use, long battery            ##
     3   35W  casual gaming, quiet               ###
     4   45W  sweet spot (perf/watt/noise)       ####
   ▸ 5   55W  sweet spot ceiling                 #####
     6   60W  serious load                       ######
     7   65W  high sustained                     ######
     8   70W  near GPD ceiling                   #######
     9   75W  GPD Motion Assistant max           #######
    10   85W  GPD sustainable max (needs force)  ########

  safe ceiling = GPD's own 75 W slider (step 9). step 10 = 85 W.
  use the 180 W barrel brick; USB-C input caps the box ~65 W.
```

## Why

AMD rates the AI Max+ 395 chip at a 45–120 W configurable TDP, but that's the
silicon, not the handheld's cooling. The real limits for the GPD WIN 5:

| Source | Limit |
|---|---|
| AMD chip (silicon) | 45–120 W cTDP, Tjmax 100 °C |
| GPD Motion Assistant slider | ships 8–75 W |
| GPD rated sustainable | 80–85 W (120 W only in short peaks) |
| Community sweet spot | 45–55 W (~95 % of peak perf, sub-80 °C) |

`tdp` maps 10 discrete steps onto that envelope, caps at GPD's own 75 W
slider maximum, and requires an explicit `--force` to go higher.

## Install

One-liner (NixOS, Ubuntu/Debian, Alpine) — installs `tdp`, `ryzenadj`, and a
boot oneshot that applies **step 5 (55 W)** by default:

```bash
curl -fsSL https://raw.githubusercontent.com/HariantoAtWork/tdp/main/install.sh | sudo bash
```

Useful flags:

```bash
# boot at 45 W instead
curl -fsSL …/install.sh | sudo bash -s -- --step 4

# binary only (no systemd / OpenRC unit)
curl -fsSL …/install.sh | sudo bash -s -- --no-service

# remove
curl -fsSL …/install.sh | sudo bash -s -- --uninstall
```

| Distro | Binary | ryzenadj | Boot service |
|---|---|---|---|
| **NixOS** | `/usr/local/bin/tdp` + `~/.local/bin/tdp` | `nix profile` / `nix-env` | via `/etc/nixos/tdp.nix` (needs rebuild) |
| **Ubuntu/Debian** | `/usr/local/bin/tdp` | built from source | systemd oneshot (immediate) |
| **Alpine** | `/usr/local/bin/tdp` | built from source | OpenRC oneshot (immediate) |

On NixOS, `/etc/systemd` is read-only, so the installer writes
`/etc/nixos/tdp.nix` and you enable it with:

```bash
curl -fsSL …/install.sh | sudo bash -s -- --rebuild
# (adds imports = [ ./tdp.nix ]; and runs nixos-rebuild switch)
```

Or edit `configuration.nix` yourself and `sudo nixos-rebuild switch`.

> Step **10** is never installed as a boot default. Raise it interactively
> with `tdp set 10 --force` only.

## The ladder

| Step | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| Watts | 15 | 25 | 35 | 45 | **55** | 60 | 65 | 70 | **75** | 85⚠ |

Step 4–5 is the daily sweet spot. Step 9 is GPD's slider max. Step 10 is
GPD's sustainable ceiling and needs `--force`.

## Usage

```bash
tdp              # print the ladder
tdp show         # same
tdp set 5        # jump to step 5 (55 W)
tdp 5            # shorthand
tdp up           # +1 step
tdp down         # -1 step
tdp set 10       # ✗ refused (above safe ceiling)
tdp set 10 --force   # ✔ apply 85 W deliberately
tdp watch        # live Tctl / GPU-watt / VRAM readout
```

## How it works

- Applies limits with [`ryzenadj`](https://github.com/FlyGoat/RyzenAdj)
  (`--stapm-limit`, `--slow-limit`, `--fast-limit`), resolved from `PATH`
  or via `nix run nixpkgs#ryzenadj --`.
- Reads live temperature / GPU power from `k10temp` and `amdgpu` hwmon.
- Manual `tdp set` is **runtime-only** and resets on reboot unless the
  installer (or a NixOS module) enabled the boot oneshot.

## Requirements

- GPD WIN 5 (or any AMD "Strix Halo" machine; the ladder is WIN 5-specific).
- root (or sudo) to write SMU power limits.
- `ryzenadj` — provided by the installer, or via `nix run nixpkgs#ryzenadj`.

## Safety notes

- Raising TDP past what the cooling can hold doesn't damage the chip — it
  thermally throttles instead — but it costs heat, fan noise and often no
  real speed gain once you're already pinned at Tjmax.
- **Use the 180 W barrel-jack PSU** for high-TDP use. USB-C input (100 W)
  caps the system around 65 W and can brownout-shutdown above that.

## License

MIT — see [LICENSE](./LICENSE).
