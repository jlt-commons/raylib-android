# Upstream findings

Things this project's lineage learned that belong to other repositories. Each
had a concrete casualty, and each was measured rather than reasoned about.

Only the findings that bear on an Android build are kept here. The rest were
made on iOS and are recorded where they were found, in
[raylib-ios](https://github.com/jlt-commons/raylib-ios): two about how jolt
names the OS on a Darwin device, and one refuted claim about raylib drawing
into framebuffer 0 under SDL, which cannot arise here because framebuffer 0 on
Android is the EGL window surface.

Nothing below has been filed. `~/.claude/rules/issue-filing-freshness.md`
applies before anything is: fetch upstream immediately before filing, re-verify
every claim against the fetched ref rather than a local tree, search the tracker
with several differently shaped queries, and re-run that search right before
submitting.

## raylib: `CUSTOMIZE_BUILD` reads a disabled option as ON

**Status:** unfiled, and inherited rather than re-measured — it comes from
`statonjr/glimmer-ios-demo`, which found it, and it is listed here because it
is a trap on any platform.

raylib's `config.h` spells a disabled option `#define SUPPORT_X 0`, and the
parser behind `CUSTOMIZE_BUILD` keys on the `#define` and ignores the value. So
customising anything flips `SUPPORT_CUSTOM_FRAME_CONTROL` and
`SUPPORT_BUSY_WAIT_LOOP` on, and under the first of those `EndDrawing` does no
swap, no timing and no event poll while `GetFPS` returns a literal 0. The tell
was `GetTime` advancing while `GetFrameTime` stayed at 0.0.

This build passes no `SUPPORT_*` flags and does not set `CUSTOMIZE_BUILD` at
all, which is the only reason it is not a live problem here.

## raylib: `GetFPS` is stateful and nothing says so

**Status:** unfiled. A documentation point, not a defect.

`GetFPS` advances a 30-slot ring by one position per call and returns
`1/sum-of-ring`, which is a frame rate only once all 30 slots are full. That
requires calling it every frame, which is what `DrawFPS` does and the only way
raylib itself ever calls it. `raylib.h` says only `// Get current FPS`.

Called once per 300 frames from a host summary it returned 1757,
then 887, 590, 441 and on down to 98 across ninety seconds, while
`GetFrameTime` held at 17.02 ms. The model `1/(n * frame-time/30)` fits all
eighteen readings to within 0.76% with no free parameters. See the README.

**Reproduced against master, on hardware, 2026-09-03.** `GetFPS` is
byte-identical at 6.0 and master `9b2efc45`, and the header comment is still
`// Get current FPS`. On a phone running a build linked against master — one
binary, one variable, the call cadence:

| cadence | readings |
|---|---|
| rare, from a cold ring (~1 call/sec) | 1773, 887, 591, 444, 354, 295, 253, 221 |
| every frame, same process moments later | 59, 59, 59, 58, 59 |

The first row is exactly `1773/n`. Both halves come from `raylib.probe`'s
`fps-every-frame?` toggle, so neither is a separate build.

Duplicate search found nothing: `GetFPS`, `GetFPS wrong`, `fps incorrect` and
`FPS_CAPTURE_FRAMES_COUNT` over all issues. The one near hit, #5597
`[rtext] DrawFPS is broken after commit 5361265`, is closed and unrelated.

**Not filed, pending a decision on shape.** The code is correct and only the
documentation is missing a precondition, so raylib's issue template ("this is
for reproducible BUGS with raylib ONLY") fits it poorly, while CONTRIBUTING
explicitly welcomes small pull requests. A one-line header change is the
natural form:

```c
RLAPI int GetFPS(void);      // Get current FPS
RLAPI int GetFPS(void);      // Get current FPS (call every frame: averages the last 30 calls)
```

Precisely: it takes at most one sample per call (gated on `FPS_STEP`, which is
`0.5f/30`), each sample being `GetFrameTime()/30` written into a 30-slot ring,
and returns `1/sum-of-ring`. So it needs 30 calls before the ring is full and
the answer means anything, which at 60 fps is half a second of per-frame calls
and never arrives if it is called from a timer.
