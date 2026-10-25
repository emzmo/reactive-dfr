# Known Issues — reactive-dfr

*Last updated: 2026-10-25*
*Found during: post-v1 audit before AUR publication*

---

## 🔴 High Priority

### 1. USB 2.0 bandwidth bottleneck (60fps)

**Description:**
The T1 chip connects via USB 2.0 (~280 Mbps practical). At 60fps, 
the display stream alone consumes ~249 Mbps (89% of bandwidth), 
leaving little for touch input, HID, and overhead.

**Technical analysis:**
The framebuffer is 2160×68 pixels in XRGB8888 format (4 bytes/pixel).
That's 2160 × 68 × 4 = 587,520 bytes per frame. At 60fps this is
~282 Mbps — essentially 100% of USB 2.0 practical bandwidth.

However, the daemon does NOT actually flush 60fps constantly. The
render loop (main.rs ~line 2822) checks a `frame_pending` flag
that combines: `needs_complete_redraw`, per-button `changed` flags,
scroll/slider/media animations, and dim transitions. When nothing
changed, the frame timer is **unset** and epoll blocks with a
longer timeout. The only constant traffic is the keep-warm
heartbeat: a 1px flush every 150ms (HEARTBEAT_INTERVAL), which
is ~4 bytes — negligible.

So the bandwidth bottleneck is real **only during active
interaction** (scrolling, slider dragging, animations). During
idle, the bus is mostly free for touch input. The problem is that
interaction is exactly when you need low touch latency — and that's
when the display is saturating the bus.

The `drm.dirty()` call sends clips via DRM damage tracking. The
kernel driver (`appletbdrm.c`) then does USB bulk transfers of
raw pixel data. There's no buffering in the daemon — each frame
is drawn to a cairo ImageSurface, copied to the DRM dumb buffer,
and flushed immediately. The USB transfer is synchronous from the
daemon's perspective (the `dirty_framebuffer` ioctl blocks until
the transfer completes).

**Impact:**
During active rendering (scroll, slider drag), touch input events
may arrive delayed because the USB bulk transfer for the display
hogs the bus. This manifests as touch lag — you drag a slider and
the response feels slightly behind. On T2 (which uses a virtual
USB host controller with more bandwidth), this is less severe.

**Strategy for v2:**
- Adaptive FPS: 60fps during interaction, 15fps for widget updates,
  5fps for static content. The `FRAME_PERIOD` constant (line ~187)
  controls the pacing — it's a single `Duration` that could be made
  dynamic based on interaction state.
- Frame skipping: the infrastructure already exists
  (`frame_pending` / `needs_complete_redraw`). The daemon already
  skips frames when idle. What's missing is a **middle tier**:
  when widgets update (every 1-5s) but there's no active touch,
  render at 15fps instead of 60fps.
- The VRR-style pacing gate (absolute deadlines, no drift
  accumulation) is well-designed and would handle variable FPS
  cleanly — just change the period.
- Risk: the keep-warm heartbeat (150ms) is calibrated for T2's
  cold-flush desync issue. On T1, the heartbeat may not be needed
  at all (T1 doesn't exhibit the T2 desync). Removing it on T1
  would free the bus entirely during idle.

---

### 2. Full-bar redraws on every widget update

**Description:**
The daemon repaints the entire Touch Bar when any widget updates, 
instead of only redrawing the changed widget.

**Technical analysis:**
This is an **intentional design decision**, not an oversight. The
code at main.rs line ~2634 has this comment:

```
// Sidestep it entirely: promote any widget change to a full-bar
// redraw so we never emit a toxic partial clip. Full-bar draw is
// cheap (~4 ms with the SVG cache), and widget ticks are seconds
// apart. (The 1px keep-warm heartbeat never stalls in the logs,
// so tiny clips are fine -- only widget-sized ones are toxic.)
```

The `draw()` function in button.rs **does support dirty rects** —
it returns `Vec<ClipRect>` of modified regions. Partial redraws
work for scroll animations (where clips are emitted). But
widget-sized partial clips were causing the appletbdrm "size
mismatch" desync on T2 hardware. The workaround is to promote any
widget change to a full-bar redraw (`needs_complete_redraw = true`).

On T1, this desync has not been observed. The T1's USB protocol
is different (preamble drain, one-behind ACK) and may handle
partial clips fine. But since the code is shared between T1 and T2,
the safe workaround is applied to both.

The full-bar redraw cost is ~4ms (cairo draw) + ~16ms (USB flush)
= ~20ms per widget update. At widget intervals of 1-5 seconds,
this is negligible. The issue only matters if many widgets update
simultaneously (e.g., CPU + battery + clock all ticking at once).

**Impact:**
Minimal on T1. The full-bar redraw is cheap and infrequent. The
real impact is on T2 where the desync was the original problem —
and the workaround solves it. On T1, we're paying a small
performance penalty for a T2 bug we may not have.

**Strategy for v2:**
- Test partial clips on T1: remove the `needs_complete_redraw`
  promotion and see if widget-sized clips cause desync. If T1
  handles them, gate the workaround on `mac_type == T2` (requires
  the daemon to know the chip type — currently it doesn't, only
  the kernel driver does).
- If partial clips work on T1, this reduces USB bandwidth during
  widget updates from 587KB to ~2-10KB per update.
- Keep the full-bar workaround for T2 unless the desync is fixed
  upstream in appletbdrm.

---

## 🟡 Medium Priority

### 3. No frame skipping (renders 60fps even when idle)

**Description:**
The daemon renders 60 frames per second regardless of whether 
anything changed.

**Technical analysis:**
This is **partially incorrect** — the daemon already implements
frame skipping. The `frame_pending` check at main.rs line ~2822
evaluates:

```rust
let frame_pending = scroll_animating
    || slider_animating
    || media_animating
    || needs_complete_redraw
    || backlight.soft_dim_animating()
    || backlight::dim_held()
    || layers[active_layer].buttons.iter().any(|b| b.1.changed);
```

When none of these are true, the frame timer is **unset**
(`frame_timer.unset()`) and epoll blocks with a longer timeout.
The bar draws **nothing** — zero frames, zero flushes (except the
150ms heartbeat). This is already an idle optimization.

What's missing is a **middle ground**: when widgets update (every
1-5 seconds) but there's no active touch interaction, the daemon
renders at full 60fps for one frame, then goes back to idle. This
is fine — it's one frame, not sustained 60fps. The issue would be
if the daemon rendered 60fps *continuously* while a widget was
"dirty", but it doesn't — it renders one frame to clear the
`changed` flag, then idles.

The only sustained 60fps scenario is during active touch
interaction (scroll, slider), which is correct — you want
smooth animation while touching.

**Impact:**
Lower than described. The daemon is already efficient when idle.
The improvement opportunity is in the interaction→idle transition:
after a scroll animation finishes, there could be a brief
"settle" period at reduced FPS before full idle.

**Strategy for v2:**
- The infrastructure exists (`frame_pending`, `FRAME_PERIOD`).
- Add a `FRAME_PERIOD_IDLE` constant (e.g., 200ms = 5fps) for
  the settle period after interaction ends.
- Or: after an animation completes, keep rendering at 15fps for
  1 second, then drop to idle. This smooths the visual
  transition without sustaining 60fps.
- Low effort: the pacing gate already handles variable periods.

---

### 4. Shared USB bandwidth (display + touch + HID)

**Description:**
USB 2.0 carries display, touch input, backlight control, and 
sensor hub all on the same bus.

**Technical analysis:**
The T1 iBridge (05ac:8600) in USB config 2 exposes multiple
interfaces on a single USB device:
- Interface 3: DFR display (2 bulk endpoints — 1 IN, 1 OUT)
- Interface 2: HID keyboard (for Touch ID / function keys)
- Interface 6: HID brightness control (Feature Reports)
- Touch digitizer (separate HID interface, handled by
  `hid-multitouch`)
- UVC webcam
- CDC-NCM (network)
- HID 0xff12 (ALS + backlight sensors)

All share the same USB 2.0 bus bandwidth. USB does not have
per-interface QoS — bulk transfers are best-effort and share
bandwidth fairly. During active display rendering (60fps), the
display bulk transfers consume ~100% of bandwidth, leaving
almost nothing for touch HID reports.

The kernel's USB scheduler (in the xHCI/EHCI driver) interleaves
transfers, but bulk endpoints are lower priority than interrupt
endpoints. Touch input uses an interrupt endpoint (not bulk),
so it has guaranteed bandwidth allocation. This means touch
input should NOT be starved by display transfers — the USB
host controller reserves bandwidth for interrupt endpoints.

However, the T1's touch digitizer might use a bulk endpoint
(we'd need to check the HID descriptor). If it does, it competes
directly with the display for bandwidth.

**Impact:**
Touch input likely does NOT suffer significant lag because HID
uses interrupt endpoints (guaranteed bandwidth). The real risk
is webcam and CDC-NCM traffic competing with display, but those
are rarely active during Touch Bar use.

**Strategy for v2:**
- Verify: check the T1's HID descriptor to confirm touch uses
  interrupt endpoints (not bulk). If yes, this issue is lower
  priority than thought.
- If touch does use bulk: reduce display FPS during interaction
  to free bandwidth.
- The backlight HID (Interface 6) uses control transfers, which
  are prioritized over bulk — no bandwidth concern there.

---

### 5. No performance profiling

**Description:**
We don't know where time is spent (render, flush, input, scripts).

**Technical analysis:**
The daemon already has built-in profiling via two environment
variables (main.rs lines ~1793-1796):

```rust
let frame_log = std::env::var_os("NQTD_FRAME_LOG").is_some_and(|v| v != "0");
let touch_log = std::env::var_os("NQTD_TOUCH_LOG").is_some_and(|v| v != "0");
```

**NQTD_FRAME_LOG=1** prints per-frame timings to the journal:
```
frame: period=16.7ms draw=3.8ms flush=14.2ms complete=true clips=1 dims(w×h)=[(2160, 68)]
```
This shows: frame period, cairo draw time, USB flush time, whether it
was a complete redraw, number of dirty clips, and their dimensions.

It also flags suspect dirty rects (zero/inverted area) that could
cause the appletbdrm desync, and logs flush failures with error
details.

**NQTD_TOUCH_LOG=1** prints touch event diagnostics:
```
touch: down slot=0 x=1234 y=34
touch: up slot=0 state=Held
```

These are **fully implemented and working** — they just need to
be enabled in the systemd unit (`Environment=NQTD_FRAME_LOG=1`)
or run manually. The data they provide is sufficient to identify
the actual bottleneck without external profiling tools.

**Impact:**
The profiling infrastructure exists but is undocumented. Users
and developers don't know about it. No one has run a profiling
session to establish baseline numbers.

**Strategy for v2:**
- Document NQTD_FRAME_LOG and NQTD_TOUCH_LOG in the README.
- Run a profiling session: 10 minutes of mixed usage (idle,
  scroll, slider, screensaver, widget updates) with
  `NQTD_FRAME_LOG=1`.
- Publish the results as a baseline.
- If the flush time is consistently >15ms, that confirms USB
  bandwidth saturation. If draw time is >5ms, cairo rendering
  is the bottleneck (unlikely — SVG cache is fast).

---

## 🟢 Low Priority

### 6. No compression on USB transfer

**Description:**
Frames are sent uncompressed (raw RGBA) over USB.

**Technical analysis:**
The framebuffer is XRGB8888 (4 bytes/pixel). The data path is:

1. cairo draws to an ImageSurface (in memory)
2. The surface data is copied to the DRM dumb buffer
3. `drm.dirty()` triggers the kernel driver to send the dirty
   regions via USB bulk transfer
4. The kernel driver (`appletbdrm.c`) sends raw pixel data —
   no compression at the DRM level

Compression could be applied at two levels:

**Userspace (daemon):** Compress the pixel data before copying
to the dumb buffer. But the DRM dumb buffer expects raw pixels —
the kernel driver reads from it and sends raw bytes over USB.
So userspace compression would require a different buffer
mechanism, not the standard DRM dumb buffer path.

**Kernel (appletbdrm.c):** Compress the USB bulk payload. The
T1 display protocol might support compressed frames (we haven't
checked). If it does, we could send RLE or zlib-compressed data
and the T1 would decompress on-chip. But the T1's display
controller is a simple framebuffer — it likely expects raw
pixels.

RLE compression would be effective for the Touch Bar because
much of the display is solid-color backgrounds (dark theme).
A row of 2160 black pixels (0x000000) would compress from
8640 bytes to ~6 bytes. But the CPU cost of RLE encoding
2160×68 pixels (~150KB) at 60fps is non-trivial — and we'd
need to modify the kernel driver, not just the daemon.

**Impact:**
Low — the daemon already skips frames when idle, so bandwidth
is only an issue during active interaction. The 60fps during
scroll is the worst case, but scroll is short-lived (1-2 seconds).

**Strategy for v2:**
- Not worth the complexity for v2. The adaptive FPS (issue #1)
  is a better solution — reducing from 60fps to 30fps halves
  bandwidth with zero CPU overhead.
- If USB bandwidth becomes critical (e.g., webcam active during
  Touch Bar use), reconsider RLE in the kernel driver.
- Check if the T1 display protocol supports any compression
  mode (read the macOS driver or the Seborider docs).

---

## Agent's Technical Assessment

### Overall architecture health

The reactive-dfr codebase is in **good shape** for a v1. The
render loop is well-designed — the VRR-style pacing gate with
absolute deadlines is the right approach, and the
`frame_pending` / `needs_complete_redraw` infrastructure means
the daemon is already efficient when idle. The T2 desync
workarounds (heartbeat, full-bar redraw promotion) are pragmatic
and well-documented in comments.

### What surprised me (positively)

1. **The daemon already skips frames when idle.** Issue #3
   ("renders 60fps even when idle") is mostly wrong — the code
   already does this. The `frame_pending` check is comprehensive
   and the timer is unset when nothing needs drawing.

2. **Dirty rect support exists** but is deliberately disabled
   for widgets. This is a T2 workaround, not a missing feature.
   The `draw()` function returns `Vec<ClipRect>` and the flush
   path handles partial clips — it's just that widget changes
   are promoted to full-bar for safety.

3. **Profiling is already built in.** NQTD_FRAME_LOG and
   NQTD_TOUCH_LOG are implemented and produce useful data.
   They just need to be documented and used.

### Risks the user didn't mention

1. **The keep-warm heartbeat is a T2 fix applied to T1.** The
   150ms heartbeat (1px flush) was designed to prevent the T2
   cold-flush desync. On T1, this desync has never been observed.
   The heartbeat generates unnecessary USB traffic on T1 (6.7
   flushes/second × 4 bytes = negligible, but still). More
   importantly, if the heartbeat flush ever stalls on T1, the
   cooldown logic kicks in and could cause a brief display
   freeze that wouldn't happen without the heartbeat. **This
   should be gated on chip type** — but the daemon doesn't
   know whether it's on T1 or T2.

2. **The daemon doesn't know the chip type.** The kernel driver
   has `mac_type` (T1 vs T2) but doesn't expose it to userspace.
   This means all T2 workarounds (heartbeat, full-bar redraw
   promotion) are applied to T1 as well. A sysfs attribute
   (e.g., `/sys/class/drm/card0/device/mac_type`) would let
   the daemon conditionally apply T2-only workarounds.

3. **The `flush_damage` path has no error recovery for T1.**
   When `drm.dirty()` fails, the daemon logs
   `"dirty flush failed: {err}"` but continues. On T2, the
   heartbeat + cooldown logic handles this. On T1, a flush
   failure might indicate the USB device was reset (S3 resume
   scenario) — the daemon should detect repeated failures
   and exit for restart (which it does for backlight writes
   but not for DRM flushes).

4. **Software dimming LUT is computed every frame.** When the
   backlight is in soft-dim mode (brightness < 100%), the
   code builds a 256-entry LUT and applies it per-pixel every
   frame (main.rs ~line 2740). This is O(587,520) per frame.
   The LUT should be cached when the dim factor doesn't change
   between frames. Minor, but it's CPU work during the
   transition that's unnecessary.

### Highest impact, lowest effort

**Expose chip type via sysfs and gate T2 workarounds.** This
one change (a few lines in `appletbdrm.c` to export a sysfs
attribute, a few lines in the daemon to read it) would:

- Disable the heartbeat on T1 (frees USB bandwidth during idle)
- Enable partial clips on T1 (reduces USB bandwidth during
  widget updates from 587KB to ~2-10KB)
- Skip the full-bar redraw promotion on T1 (faster widget updates)
- Make the T2 desync workarounds truly T2-only

This is the single change with the biggest performance impact
on T1, and it requires minimal code modification.

---

*Last updated: 2026-10-25*
*Found during: post-v1 audit before AUR publication*