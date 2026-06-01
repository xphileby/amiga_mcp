# Set Up FS-UAE Emulator for Amiga DevBench

Configure FS-UAE (or AmiKit) to work with the Amiga DevBench development environment.

## Arguments
- $ARGUMENTS: Platform or specific issue (e.g., "mac", "linux", "windows", "serial not connecting", "amikit"). If empty, detect platform and walk through full setup.

## Two paths: AmiKit (easy) or FS-UAE standalone

### Path A: AmiKit (macOS, recommended)
AmiKit bundles everything (Workbench, ROMs, pre-configured drives). Easiest way to get started.

1. **Install AmiKit**: Download from https://www.amikit.amiga.sk/
2. **Run the configure script**:
   ```bash
   ./scripts/configure-amikit.sh
   ```
   This patches AmiKit's WinUAE configs to enable serial-over-TCP on port 1234 and creates the shared Dev folder.

3. **Restart AmiKit** — the serial port is now active.

4. **Configure devbench.toml**:
   ```toml
   [serial]
   mode = "tcp"
   host = "127.0.0.1"
   port = 1234

   [emulator]
   config = "/Users/YOU/Documents/FS-UAE/Configurations/AmiKit-Debug.fs-uae"
   auto_start = true

   [paths]
   deploy_dir = "/Applications/AmiKit.app/Contents/SharedSupport/prefix/drive_c/AmiKit/Dropbox/Dev"
   ```

5. **Start devbench**: `make start`

### Path B: FS-UAE Standalone (any platform)

#### Step 1: Install FS-UAE
- **macOS**: `brew install --cask fs-uae`
- **Linux**: `sudo apt-get install fs-uae` or Flatpak: `flatpak install flathub net.fsuae.FS-UAE`
- **Windows**: Download from https://fs-uae.net/download

#### Step 2: Get Kickstart ROM
FS-UAE needs Amiga Kickstart ROM files. Legal options:
- **Amiga Forever** (commercial): https://www.amigaforever.com/ — includes all ROMs
- **Cloanto Amiga OS ROMs** — bundled with Amiga Forever
- Place ROM files in `~/Documents/FS-UAE/Kickstarts/` (macOS/Linux) or `%USERPROFILE%\Documents\FS-UAE\Kickstarts\` (Windows)

Required ROM: Kickstart 3.1 (A1200) — file usually named `kick31.rom` or `amiga-os-310-a1200.rom`

#### Step 3: Create a hard drive directory
```bash
mkdir -p ~/Documents/FS-UAE/Hard\ Drives/System
mkdir -p ~/amiga-shared
```
You'll need a Workbench 3.1 install on the System drive (or use AmiKit which provides this).

#### Step 4: Create FS-UAE config file

There's a sample config at the project root: `AmiKit-Debug.fs-uae`. Copy and customize it:

```bash
mkdir -p ~/Documents/FS-UAE/Configurations/
cp AmiKit-Debug.fs-uae ~/Documents/FS-UAE/Configurations/DevBench.fs-uae
```

Then edit the copy — the **critical settings** are:

```ini
[fs-uae]
# CPU and memory
amiga_model = A1200
cpu = 68060
chip_memory = 2048
fast_memory = 8192

# Kickstart ROM path (CHANGE THIS)
kickstart_file = /path/to/your/kick31.rom

# Hard drives (CHANGE THESE)
hard_drive_0 = /path/to/System               # Bootable Workbench
hard_drive_0_label = System

hard_drive_2 = /path/to/amiga-shared         # Shared folder for deploying binaries
hard_drive_2_label = Dev

# SERIAL PORT — this is the key setting for DevBench
serial_port = tcp://0.0.0.0:1234

# Display
window_width = 800
window_height = 600
fullscreen = 0

# Mouse integration (don't capture mouse)
mouse_integration = 1
automatic_input_grab = 0
```

#### Step 5: Configure devbench.toml
```toml
[serial]
mode = "tcp"
host = "127.0.0.1"
port = 1234

[emulator]
binary = "fs-uae"     # or full path like /usr/bin/fs-uae
config = "/path/to/Documents/FS-UAE/Configurations/DevBench.fs-uae"
auto_start = true

[paths]
deploy_dir = "/path/to/amiga-shared"
```

#### Step 6: Test
```bash
# Start devbench (will auto-start emulator if configured)
make start

# Or start emulator manually first, then devbench
fs-uae ~/Documents/FS-UAE/Configurations/DevBench.fs-uae &
python3 -m amiga_devbench
```

Open http://localhost:3000 — the Dashboard should show the emulator status and the connection indicator should go from red → yellow → green once the bridge daemon starts on the Amiga.

## Web UI Config

Once devbench is running, you can edit the FS-UAE config directly from the browser:
1. Go to http://localhost:3000
2. Click the **Settings** tab
3. The **Config** sub-tab shows devbench.toml settings (serial, emulator path, deploy dir)
4. Below that is a **full FS-UAE config editor** with Save & Restart Emulator button

## Optional: Patched FS-UAE with HTTP debugger (CPU-level inspection)

The standard FS-UAE only exposes its debugger interactively via the GUI. For
scripted / MCP-driven CPU debugging — pausing, register inspection, hardware
breakpoints/watchpoints, disassembly, memory map — install the patched
fork at https://github.com/geekychris/fsuae_remote_patch.

What it adds (when enabled):
- An HTTP/JSON-RPC server on `127.0.0.1:8765` (configurable) inside fs-uae
- A "FS-UAE" tab in the devbench Web UI with live CPU regs, disasm, BP/WP
- 27 new MCP tools (`amiga_fsuae_pause`, `amiga_fsuae_cpu`,
  `amiga_fsuae_disasm`, `amiga_fsuae_breakpoint_add`,
  `amiga_fsuae_watchpoint_add`, etc.) — see `mcp_fsuae.py` upstream
- Optional in-emulator GDB stub on a second port (`FSUAE_GDB_PORT`)

The patch is **off by default** in the patched binary — it only activates
when `FSUAE_RPC_PORT` is set in the environment. Devbench sets it
automatically based on `[fsuae_rpc]` in `devbench.toml`. Stock fs-uae
ignores the env var, so you can leave the config enabled regardless of
which build is installed.

### Install

```bash
git clone https://github.com/geekychris/fsuae_remote_patch.git
cd fsuae_remote_patch
./build.sh   # ~12s on Apple Silicon; clones fs-uae v3.2.35, patches, builds
# Binary lands at /tmp/fsuae-src/fs-uae/fs-uae (and the script copies it nearby)
```

### Wire into devbench

In `devbench.toml`:

```toml
[emulator]
# Point at the patched binary
binary = "/path/to/fsuae_remote_patch/fs-uae"
config = "/path/to/your/config.fs-uae"
auto_start = true

[fsuae_rpc]
enabled = "auto"          # "auto" probes; "on" forces; "off" disables
port = 8765
pause_at_boot = false     # set true to pause before the first instruction runs
gdb_port = 0              # nonzero enables the in-emulator GDB stub
```

Then `make start`. The Web UI's header gets an "RPC" badge (green = live,
grey = probing, red = error) and a new **FS-UAE** tab appears. From MCP,
call `amiga_fsuae_status` first to check availability before issuing other
`amiga_fsuae_*` tools.

### Verify

```bash
curl http://127.0.0.1:8765/v1/ping
# {"ok":true,"service":"fs-uae-rpc v1"}
curl http://127.0.0.1:3000/api/fsuae/status
# {"status":"available","base_url":"http://127.0.0.1:8765",...}
curl http://127.0.0.1:3000/api/emulator/status
# {..., "configured_binary":"auto", "binary":"/tmp/fsuae-src/fs-uae", "patched":true}
```

### What you get when the patched build is active

The Web UI grows a new top-level **FS-UAE** tab with four sub-tabs:

| Sub-tab | What's in it |
|---|---|
| **CPU & Breakpoints** | Live disassembly (library-call annotation + optional source xref), CPU registers (click value to edit), CPU breakpoints with skip-count + one-shot, memory watchpoints with R/W/I + mustchange + "last hit" PC display |
| **Memory** | Hex viewer with byte/word/longword/ASCII formats and click-a-longword-to-follow-pointer navigation (with ← back history), memory writer, memory map, stack walk |
| **Chipset** | One-click snapshot of DMACON, INTENA/INTREQ, BPLCONx, copper / bitplane pointers, beam position |
| **State & Symbols** | **Snapshot slots 1-9** (quick savestates with 1-9 keyboard shortcuts; Shift+N saves, N loads), snapshot diff (chunk-level via `uss_diff.py`), custom-path snapshot save/load, symbol lookup, FD library offset lookup, FD library loader |

### Auto-snapshot ring (opt-in, off by default)

Devbench can periodically save state to a rotating ring of `.uss` files, giving you approximate rewind for forensic debugging. **Has perceptible perf impact** (~200ms stall every interval) so it's strictly opt-in:

```toml
[fsuae_rpc]
auto_snapshot_interval_s = 0     # 0 = off. Set to e.g. 30 to enable.
auto_snapshot_ring_size = 5      # rotating slots
```

Or toggle at runtime from the State & Symbols sub-tab → "AUTO-SNAPSHOT RING" panel. Files land at `~/.amiga-devbench/snapshots/auto-N.uss`.

### Symbolic breakpoints

Set a fs-uae CPU breakpoint by function name (resolved against bridge symbols loaded in the Debugger tab):

- UI: CPU & Breakpoints sub-tab → enter a function name in the BP input → click **+ BP @symbol**
- MCP: `amiga_fsuae_breakpoint_by_symbol("draw_ball")`
- HTTP: `POST /api/fsuae/breakpoints/by-symbol?name=draw_ball`

Requires symbols to have been loaded first (Debugger tab → Load Symbols, or `amiga_load_symbols`).

### Push events + auto-pause

Devbench connects to fs-uae's `/v1/events` WebSocket and republishes frames on its own SSE bus, so the UI gets push notifications:

- The FS-UAE tab auto-refreshes the moment the emulator pauses (no Refresh button needed)
- The tab flashes amber on watchpoint fire or auto-pause
- The auto-pause on bridge crash (`[fsuae_rpc] auto_pause_on_crash = true`) freezes the CPU at the fault moment for inspection

MCP-wise, the `amiga_fsuae_*` family (27 tools) becomes useful: `amiga_fsuae_pause`, `amiga_fsuae_cpu`, `amiga_fsuae_disasm`, `amiga_fsuae_breakpoint_add`, `amiga_fsuae_watchpoint_add`, `amiga_fsuae_memmap`, `amiga_fsuae_state_save`, etc. Each tool checks RPC availability first and returns a clear "install the patched build" hint when stock fs-uae is in use, so it's always safe for the agent to attempt them.

HTTP-wise, 28 routes under `/api/fsuae/*` mirror the same surface for curl / shell use.

### When NOT to use

If you don't need CPU-level / pre-boot / ROM debugging, the standard
fs-uae build is fine. The bridge daemon-based debugger (`Debugger` tab,
`amiga_debugger_*` MCP tools) already covers source-level debugging for
your own apps. The patched build adds emulator-level visibility on top.

The two debuggers complement each other and run side-by-side without interfering:
- **Bridge debugger** — when you need source-level visibility into *your own app*
- **FS-UAE debugger** — when you need CPU-level visibility into the *whole machine* (ROM, pre-boot, hardware state, post-crash inspection)

## Serial Connection: How It Works

```
FS-UAE                          DevBench
 |                                |
 | serial_port=tcp://0.0.0.0:1234|
 | (listens on port 1234)        |
 |                                |
 |<------TCP connect-------------|  (devbench connects as client)
 |                                |
 | serial.device ←→ TCP socket   |
 |                                |
 Amiga bridge daemon              Python server
 (reads/writes serial.device)     (reads/writes TCP socket)
```

The Amiga program uses `serial.device` normally. FS-UAE tunnels that over TCP. DevBench connects to that TCP port.

## Troubleshooting

- **Connection refused on port 1234**: FS-UAE must be running BEFORE devbench tries to connect. Check that `serial_port = tcp://0.0.0.0:1234` is in the FS-UAE config.
- **Yellow indicator (serial connected but no bridge)**: The bridge daemon needs to be started on the Amiga side: `DH2:Dev/amiga-bridge` (or `AK2:Dev/amiga-bridge` on AmiKit)
- **"No Kickstart ROM"**: FS-UAE can't find the ROM. Check `kickstart_file` path.
- **Emulator starts but black screen**: Workbench not installed on DH0. You need a bootable system drive.
- **Shared folder not visible on Amiga**: Check `hard_drive_2` path exists and the label matches what you expect (`Dev:` or `DH2:`).
