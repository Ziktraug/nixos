# Game Launch Options Guide

This guide covers how to configure launch options for games on KDE Plasma 6 with Wayland, with special focus on HDR support and Gamescope integration.

## Table of Contents

- [Quick Start](#quick-start)
- [HDR Setup](#hdr-setup)
- [Gamescope Launch Options](#gamescope-launch-options)
- [Steam Integration](#steam-integration)
- [Heroic Integration](#heroic-integration)
- [Display Configuration Reference](#display-configuration-reference)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### Enable HDR in Your Games (with GameMode)

**For Steam (native HDR games) - RECOMMENDED:**

```bash
gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 -- %command%
```

**For Steam (Proton games with ITM):**

```bash
gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 --hdr-itm-enabled -- %command%
```

**For Heroic (Epic/GOG games):**
Same as above - Heroic uses the same Proton/Wine stack as Steam.

**Without HDR (SDR gaming with performance boost):**

```bash
gamemoderun %command%
```

---

## GameMode Integration

### What is GameMode?

GameMode is a daemon/library that optimizes Linux system performance for gaming by:

- Switching CPU governor to `performance` mode
- Adjusting process scheduling priorities and niceness
- Setting GPU performance profiles
- Disabling screen savers
- Optimizing I/O priorities

The public example enables GameMode in its [module selection](../../hosts/example/modules.nix), including start/stop notifications.

### Using GameMode with Gamescope

**Recommended order:**

```bash
gamemoderun gamescope [OPTIONS] -- %command%
```

**Why this order?**

- `gamemoderun` applies performance optimizations to the entire process tree
- `gamescope` (the compositor) inherits these optimizations
- Your game runs inside the optimized gamescope environment
- Result: Both compositor AND game get performance benefits

### GameMode Commands

**With HDR:**

```bash
gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 -- %command%
```

**Without Gamescope (traditional):**

```bash
gamemoderun %command%
```

### Verifying GameMode is Active

When you launch a game with `gamemoderun`, you should see a notification:

- "GameMode started" when the game launches
- "GameMode ended" when the game closes

You can also check manually:

```bash
# Check if gamemode is running for any process
gamemoded -s

# List processes currently using gamemode
ps aux | grep gamemode
```

---

## HDR Setup

### Understanding Your Display

Your OLED display (DP-3) has these HDR capabilities:

```
Resolution: 3840×2160 @ 240Hz
HDR: Enabled
Wide Color Gamut: Enabled
SDR Brightness: 430 nits
Peak Brightness: 430 nits (overridden)
Max Average Brightness: 265 nits
Min Brightness: 0.0003 nits
```

### How HDR Works on Linux

1. **Windows Model**: Games query the display directly via DXGI
2. **Linux Model**: The compositor (KWin) owns the display, so games need **Gamescope** as a bridge

**Gamescope's Role:**

- Creates a nested Wayland compositor
- Exposes HDR capabilities to games via the Vulkan WSI (Wayland Surface Interface) layer
- Handles tone-mapping when needed
- Composites the final output back to KWin

### Why Games Don't Detect HDR by Default

Without Gamescope:

- Games see the Wayland surface as SDR-only
- HDR queries return "not supported"
- HDR rendering is disabled or tone-mapped to SDR

With Gamescope (properly configured):

- The WSI layer reports HDR10 support
- Games can query and use HDR capabilities
- Peak brightness, color gamut, and tone-mapping are available

---

## Gamescope Launch Options

### Basic Syntax

```bash
gamescope [GAMESCOPE_OPTIONS] -- [GAME_COMMAND]
```

### Resolution & Refresh Rate

```bash
-W 3840 -H 2160     # Width and height (your display native resolution)
-r 240              # Refresh rate (240Hz for your OLED)
```

**Why these matter:**

- Matching your native resolution ensures no scaling artifacts
- High refresh rate (240Hz) is why you have your OLED - use it!

### HDR Options

#### Primary HDR Flag

```bash
--hdr-enabled
```

**What it does:**

- Enables HDR output mode
- Gamescope will output HDR10 PQ (Perceptual Quantization) to KWin
- Games can now detect and use HDR

#### SDR Content Brightness (Critical for HDR)

```bash
--hdr-sdr-content-nits 430
```

**What it does:**

- Sets the reference brightness for SDR content in your HDR pipeline
- Games mix SDR UI elements with HDR visuals
- Value should match your typical SDR display brightness

**Your Values:**

- `430 nits` - Your display's configured SDR brightness
- If you adjust in KDE Settings → Display & Monitor → HDR, update this value

**How to find the right value:**

1. Open **System Settings → Display & Monitor → HDR**
2. Look at "SDR brightness" value
3. Use that value in the launch option

#### Inverse Tone Mapping (SDR→HDR Upscaling)

```bash
--hdr-itm-enabled
```

**What it does:**

- Upscales SDR game visuals to use more of the HDR color space
- Makes old SDR games look richer on your OLED
- Only works when input is SDR

**When to use:**

- Older games (pre-2020)
- Proton games that may not have proper HDR support

**Advanced ITM Options:**

```bash
--hdr-itm-sdr-nits 400        # Input SDR brightness for ITM
--hdr-itm-target-nits 1000    # Target peak brightness after upscaling
```

#### Debug Options (Development Only)

```bash
--hdr-debug-force-support     # Force HDR reporting even if display doesn't support it
--hdr-debug-force-output      # Force HDR10 output (will look wrong on SDR displays!)
--hdr-debug-heatmap           # Show luminance heatmap overlay (very useful for testing)
```

### Color Management

```bash
--disable-color-management    # Disable Gamescope's color processing
```

**When to use:**

- If you have a custom ICC profile and want to handle color management yourself
- For most users, leave this disabled (Gamescope handles it well)

### GPU Selection

```bash
--prefer-vk-device 10de:2206  # Use specific GPU (NVIDIA device ID)
```

**Your GPU:**

- NVIDIA GeForce RTX 3080
- Device ID: `10de:2206`

**When to use:**

- Multi-GPU systems
- Force GPU selection if Gamescope picks the wrong one

### Common Full Options

#### For Modern HDR Games (Recommended)

```bash
gamemoderun gamescope -W 3840 -H 2160 -r 240 \
  --hdr-enabled \
  --hdr-sdr-content-nits 430 \
  -- %command%
```

#### For Older SDR Games (with Upscaling)

```bash
gamemoderun gamescope -W 3840 -H 2160 -r 240 \
  --hdr-enabled \
  --hdr-sdr-content-nits 430 \
  --hdr-itm-enabled \
  --hdr-itm-sdr-nits 400 \
  --hdr-itm-target-nits 1000 \
  -- %command%
```

#### For Performance (Lower Resolution)

```bash
gamemoderun gamescope -W 1920 -H 1080 -r 240 \
  --hdr-enabled \
  --hdr-sdr-content-nits 430 \
  -- %command%
```

---

## Steam Integration

### Setting Launch Options

1. **Right-click game → Properties**
2. **General tab → Launch Options field**
3. **Paste your Gamescope command**

### Example Steam Launch Options

**Baldur's Gate 3 (HDR-capable):**

```bash
gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 -- %command%
```

**Elden Ring (via Proton, with ITM):**

```bash
gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 --hdr-itm-enabled -- %command%
```

**Cyberpunk 2077 (native, full HDR):**

```bash
gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 -- %command%
```

**Without HDR (traditional GameMode only):**

```bash
gamemoderun %command%
```

### Verifying HDR is Working

In-game, check:

1. **Graphics Settings** for HDR toggle (may say "HDR10" or "Dolby Vision")
2. **NVIDIA FrameView** overlay shows HDR mode active
3. **Gamescope debug heatmap** shows luminance values > 1000 nits

---

## Heroic Integration

### Finding Game Settings

1. **Heroic Launcher → Your Game**
2. **⚙️ Settings button**
3. **Proton/Wine settings**
4. **Advanced section**

### Adding Gamescope Command

In Heroic's **Advanced launch arguments** or **Wine prefix environment**, add:

```bash
gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 --
```

Or in the game's **Target** field:

```bash
/run/current-system/sw/bin/gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 -- %command%
```

### Heroic + Gamescope Notes

- **Gamescope.enable = true** in your modules.nix (already enabled ✓)
- Heroic automatically provides Gamescope in the sandbox
- Use full paths or rely on Heroic's environment setup

---

## Display Configuration Reference

### Your Display Configuration

Get your display info anytime with:

```bash
kscreen-doctor -o
```

### Current Settings

| Parameter | Value |
|-----------|-------|
| Output | DP-3 (DisplayPort) |
| Resolution | 3840×2160 @ 240Hz |
| Position | 1080, 0 (right side) |
| Scaling | 1.45× (for UI scaling) |
| Rotation | 90° (portrait/vertical) |
| HDR | Enabled |
| Wide Color Gamut | Enabled |
| SDR Brightness | 430 nits |
| Peak Brightness | 430 nits |
| Max Avg Brightness | 265 nits |
| Min Brightness | 0.0003 nits |

### Adjusting Display Settings

**Via GUI:**

1. **System Settings → Display and Monitor**
2. **HDR tab** - adjust brightness and peak values
3. Apply and note the new values

**Via Command Line:**

```bash
# Get current settings
kscreen-doctor -o

# Change brightness (requires kscreen-doctor script customization)
# Most settings are GUI-only in KDE Plasma 6
```

### HDR Settings in KDE

**System Settings → Display and Monitor → HDR:**

- **SDR Brightness**: How bright SDR content should be (default: 430 nits)
- **SDR Gamut Wideness**: How much wide-gamut to apply to SDR (0-100%, default: 0%)
- **Peak Brightness Override**: Cap HDR peak brightness

---

## Troubleshooting

### Games Not Detecting HDR

**Symptom:** HDR option not available in game settings

**Solutions:**

1. **Verify Gamescope is running:**

   ```bash
   ps aux | grep gamescope
   ```

2. **Check WSI layer is loaded:**

   ```bash
   gamescope --hdr-debug-force-support -W 100 -H 100 -r 60 -- true 2>&1 | grep -i hdr
   ```

3. **Test with debug heatmap:**

   ```bash
   gamescope -W 3840 -H 2160 -r 240 \
     --hdr-enabled \
     --hdr-sdr-content-nits 430 \
     --hdr-debug-heatmap \
     -- /path/to/game
   ```

   You should see a colored heatmap overlay showing luminance values.

4. **Ensure game supports HDR:**
   - Not all games support HDR
   - HDR is mostly available in modern AAA titles (2020+)
   - Some games have HDR disabled by default

### Colors Look Wrong / Washed Out

**Symptom:** Game colors appear desaturated or incorrect

**Causes & Solutions:**

1. **Tone-mapping mismatch:**
   - Remove `--hdr-itm-enabled` if present
   - Adjust `--hdr-sdr-content-nits` value

2. **OLED color space issue:**
   - Your display is DCI-P3 wide-gamut
   - Some games may not handle wide-gamut correctly
   - Try `--disable-color-management` as test

3. **NVIDIA color management:**
   - Check NVIDIA settings for color adjustments
   - Run: `nvidia-settings` (may require Xwayland)

### Game Crashes with Gamescope

**Symptom:** Game crashes immediately or on load

**Causes:**

1. **Incompatible game/Proton version**
   - Try without Gamescope first
   - Update Proton via ProtonUp-Qt

2. **Display resolution mismatch:**
   - Wrong `-W` or `-H` values
   - Try matching your display exactly: `3840x2160`

3. **Refresh rate issue:**
   - Try lower refresh: `--refresh 120`
   - Your display supports up to 240Hz, but some games may not

**Debug:**

```bash
# Run game with verbose output
gamescope -W 3840 -H 2160 -r 240 --hdr-enabled -- /path/to/game 2>&1 | tail -50
```

### HDR Working in Gamescope But Not in Game

**Symptom:** Heatmap shows HDR, but game doesn't enable HDR option

**Causes:**

1. **Game doesn't support HDR** (not all do)
2. **WSI layer not properly loaded:**
   - Verify in game logs
   - Some engines (Unreal Engine) need special flags

3. **Proton/Wine version mismatch:**
   - Update via ProtonUp-Qt
   - Try newest Proton Experimental

**Solution:**

```bash
# Force HDR reporting for testing
gamescope -W 3840 -H 2160 -r 240 \
  --hdr-debug-force-support \
  --hdr-enabled \
  --hdr-sdr-content-nits 430 \
  -- %command%
```

### Performance Issues with Gamescope

**Symptom:** FPS drops, stuttering, or lag

**Causes:**

1. **Nested composition overhead:**
   - Gamescope composites twice (game → Gamescope, Gamescope → KWin)
   - Small performance cost but usually minimal on RTX 3080

2. **High resolution/refresh combo:**
   - 3840×2160 @ 240Hz is demanding
   - Try reducing to 120Hz or 1920×1080 if needed

3. **HDR processing overhead:**
   - Tone-mapping and color conversion cost CPU/GPU
   - Try `--disable-color-management` as test

**Solutions:**

```bash
# Lower resolution for testing
gamescope -W 1920 -H 1080 -r 240 --hdr-enabled -- %command%

# Lower refresh rate
gamescope -W 3840 -H 2160 -r 120 --hdr-enabled -- %command%

# Disable color management (if not critical)
gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --disable-color-management -- %command%
```

### OLED Color Shifts During Gaming

**Symptom:** Colors shift or brightness dims during gameplay

**This is normal OLED behavior:**

1. **OLED Brightness Limiting (ABL):** Large bright areas trigger dimming
2. **Thermal management:** Panel reduces brightness as it heats
3. **Pixel refresh cycles:** Periodic maintenance cycles may cause brief dimming

**Mitigation:**

1. In **KDE Settings → Display → HDR**, reduce "Peak Brightness Override"
2. In-game, reduce brightness if sliders available
3. Check monitor's OSD for "OLED care" features and adjust as needed

**This is not a bug** - it's how OLED displays preserve panel longevity.

---

## Performance Monitoring

### Monitor HDR Rendering

While gaming with Gamescope HDR enabled:

```bash
# Monitor GPU usage
watch -n1 'nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used --format=csv,noheader,nounits'

# Monitor with detailed info
nvidia-smi -l 1
```

### Check Gamescope is Using HDR

```bash
# Look for HDR in Gamescope process
ps aux | grep gamescope | grep hdr
```

### Verify Display HDR Status

```bash
# Check if display reports HDR as active
kscreen-doctor -o | grep -A20 "DP-3" | grep -i hdr
```

---

## Advanced Configuration

### Custom Gamescope Wrapper Script

Create `~/.local/bin/gamescope-hdr` for easier launching:

```bash
#!/bin/bash
# Gamescope HDR wrapper with GameMode for quick launching

GAME_CMD="$@"
DISPLAY_WIDTH=3840
DISPLAY_HEIGHT=2160
DISPLAY_RATE=240
SDR_NITS=430

exec gamemoderun gamescope \
  -W $DISPLAY_WIDTH \
  -H $DISPLAY_HEIGHT \
  -r $DISPLAY_RATE \
  --hdr-enabled \
  --hdr-sdr-content-nits $SDR_NITS \
  -- "$GAME_CMD"
```

Usage:

```bash
chmod +x ~/.local/bin/gamescope-hdr
gamescope-hdr /path/to/game
```

### Per-Game Launch Profiles

Create a library of launch commands for reference:

```bash
# Cyberpunk 2077 (native + modern HDR)
CYBERPUNK="gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 -- %command%"

# Baldur's Gate 3 (Vulkan + HDR)
BG3="gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 -- %command%"

# Elden Ring (Proton + ITM for compatibility)
ELDEN="gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 --hdr-itm-enabled -- %command%"

# Older games (lower res + ITM)
RETRO="gamemoderun gamescope -W 1920 -H 1080 -r 120 --hdr-enabled --hdr-sdr-content-nits 430 --hdr-itm-enabled -- %command%"

# Without HDR (just performance optimization)
STANDARD="gamemoderun %command%"
```

---

## Resources

- [Gamescope Documentation](https://github.com/ValveSoftware/gamescope)
- [GameMode Documentation](https://github.com/FeralInteractive/gamemode)
- [KDE Plasma Display Settings](https://docs.kde.org/stable5/en/kcontrol/kcm_kscreen/index.html)
- [Vulkan WSI Documentation](https://www.khronos.org/vulkan/)
- [NVIDIA Developer Documentation](https://developer.nvidia.com/nvidia-developer-program)

---

## Quick Reference Cheat Sheet

```bash
# Basic HDR gaming with GameMode (RECOMMENDED)
gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 -- %command%

# With inverse tone-mapping for SDR games
gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 --hdr-itm-enabled -- %command%

# Performance mode (1080p)
gamemoderun gamescope -W 1920 -H 1080 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 -- %command%

# Debug mode (show HDR heatmap)
gamemoderun gamescope -W 3840 -H 2160 -r 240 --hdr-enabled --hdr-sdr-content-nits 430 --hdr-debug-heatmap -- %command%

# Without HDR (just GameMode performance boost)
gamemoderun %command%

# Test without Gamescope or GameMode (baseline)
%command%

# Check if game sees HDR
# Look in game settings for "HDR" or "HDR10" option

# Verify GameMode is active
gamemoded -s
```

---

**Last Updated:** January 2026

**For questions or updates**, check the [nixos modules documentation](../README.md) or the [main NixOS guide](../../CLAUDE.md).
