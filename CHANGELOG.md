# Changelog

Notable changes, newest first. Dates are the day the work landed.

## 2026-09-03 (Android)

The iOS host is replaced by an Android one. Same seventeen scenes, same pure
`.cljc` under them, same scene contract; everything between that contract and
the glass is new. Not yet run on hardware — see the note at the top of
`tools/android/RUNBOOK.md`.

### Added

- **An Android NativeActivity host.** `raylib.host` owns the frame loop on the
  thread `android_main` hands over, with no SDL: raylib's own
  `src/platforms/rcore_android.c` is the platform layer, compiled from pinned
  source straight into `libmain.so`.
- **A twenty-line C bootstrap**, `tools/android/app/src/main/cpp/main.c`. It
  implements the `extern int main(int, char **)` contract raylib's
  `android_main` calls, dlopens the `jolt build --library` output, and resolves
  the frame loop through `jolt_lookup`. Every step is a logcat line, because a
  failure before the first frame is otherwise a black screen.
- **Native arm64 code**, `tarm64le`, where the iOS build had to be threaded
  portable bytecode: iOS requires executable pages to come from a signed,
  immutable source and Android does not.
- **`raylib.host/log`**, and every diagnostic routed through it. An Android
  app's stdout goes to `/dev/null`, so `println` wrote into nothing; this calls
  `__android_log_write` and `jolt log` reads it back.
- **`raylib.host/finish!`, and Back that means something.** The pinned
  `rcore_android.c` records `AKEYCODE_BACK` and then eats the event, so it
  never reaches Android and never sets `shouldClose`. The gallery reads it as
  one level up — scene, category list, categories, quit — and quitting returns
  from the loop, from `main`, and into `ANativeActivity_finish`. The iOS host
  had to ignore the same request.
- **A display density recovered from raylib's own arithmetic.**
  `GetWindowScaleDPI` is unimplemented on Android, but `GetMonitorPhysicalWidth`
  is `(widthPixels/dpi)*25.4`, so dividing back recovers
  `AConfiguration_getDensity` to within its integer truncation. 1080 px over
  57 mm gives 481 dpi where the device says 480.
- **`tools/android/`**: `deps.sh` (the pinned raylib source), `pack.sh` (Chez
  10.4.1 cross-built against Bionic, `-fPIC`, `--disable-iconv`), `build.sh`
  (`jolt build --library` then Gradle), `deploy.sh`, `log.sh`, `devices.sh`,
  `proxy.sh`, `live.sh`, a Gradle module, and a RUNBOOK.
- **`tools/android/nrepl`**, a dependency-free nREPL client in Python, in place
  of the two babashka scripts. Bencode is forty lines and this is the one piece
  of tooling wanted before anything else is installed.
- **`raylib.probe/gl-report`**, which asks the device which GLES driver it is.

### Changed

- **`deps.edn`'s `:jolt/native` names `libmain.so`**, optional, so Chez
  resolves raylib against the NativeActivity image rather than the global
  scope. `__android_log_write` comes through the same handle, out of
  `liblog.so`'s DT_NEEDED entry.
- **`:jolt/min-version` is 0.8.1**, not 0.8.0. This build is a `--library`
  cross-compile of a source-mode image, and jolt#756 — fixed in 0.8.1 — left
  `jolt.ffi`'s own Clojure layer interned but unbound in exactly that
  combination.
- **Debug and release stage their libraries apart**, in AGP's per-variant
  `jniLibs` directories, so a release APK cannot pick up a debug library that
  is still lying about. A debug library is the one with the nREPL in it.
- **The nREPL is structurally debug-only.** Only the debug manifest asks for
  `INTERNET`, and `main.c` refuses to run a release image in which the nREPL
  entry point exists at all.
- **`raylib.live` no longer reads a port from the environment.** An Android app
  inherits none, and Intent extras do not reach a NativeActivity's C `main`.
- **The docs, the site and CI** are `raylib-android`, base path included.
  Every image and frame time still comes from the iPhone and now says so.

### Removed

- **`raylib.objc`** — there is no Objective-C runtime to talk to.
- **`raylib.link`** — it probed the two iOS static archives. `main.c`'s
  bootstrap logging answers the same question now.
- **SDL2, entirely.** It existed because raylib has no iOS backend.
- **The framebuffer juggling and the safe-area query.** raylib renders into a
  real framebuffer 0 here, and the manifest's fullscreen theme without
  `shortEdges` keeps the window clear of a display cutout, so `:inset-top` is
  honestly 0.
- **`tools/ios/`.**

## 2026-09-03 (later)

### Added

- **Two scenes, seventeen in total.** `lorenz`, the Lorenz attractor with a
  hand-rolled orbiting camera since this host binds none of raylib's 3D, and
  `tesseract`, a 4D hypercube projected 4D to 3D to 2D.
- **`raylib.scenes.lorenz/trail-length` is an atom**, not a `def`, so the
  performance ceiling can be swept from a REPL without a rebuild.

### Fixed

- **The test runner silently skipped new test files.** Its namespace list was
  hardcoded, so two new `*_test.cljc` files never ran and `Ran 23 tests` read
  as a pass. The runner now compares the list against what is on disk and fails
  if a test file is not listed.
- **Lorenz allocated per segment**, a fresh vector from both `project` and
  `trail-colour`, about 2400 a frame. 18 fps before, 31 after, 58 once the
  trail was sized from the sweep.
- **The trail could open on half a butterfly.** A 450-point window is short
  enough to sit inside one lobe: 499 frames of 600 straddle both. `warm` now
  runs on until the window spans the divide.

### Measured

- Lorenz's ceiling: flat at vsync to a 480-point trail, slipping at 500,
  falling away past 600. Default set to 450 at 58 fps.
- Euler at `dt` 0.006 tracks a near-exact reference; 0.009 and 0.012 inflate
  the attractor, so a bigger step does not buy more trajectory per point.

## 2026-09-03

The whole project, in one day. raylib and SDL2 rendering on an iPhone from
Clojure, fifteen scenes, and the measurements that shaped them.

### Added

- **zlib licence**, in `LICENSE`, matching raylib-jlt, raylib and SDL2. See
  `NOTICE` for third-party provenance and for the one blocker that has to clear
  before this repository can be published or transferred.
- **raylib 6.0 and SDL2 on iOS.** raylib ships no iOS platform layer and needs
  none: built `PLATFORM=SDL` with `GRAPHICS_API_OPENGL_ES2` against an SDL2
  compiled for iOS, SDL's own iOS support becomes the platform layer. Both go
  into the executable as static archives, because `jolt build --target` emits
  the whole binary and Chez owns `main`.
- **`raylib.host`**, the owner loop. Chez's `main` calls `SDL_UIKitRunApp`
  through the FFI, SDL runs `UIApplicationMain`, and its delegate calls back on
  thread 0, where the raylib loop lives for the life of the app.
- **Fifteen scenes** in four categories. Six are pure `.cljc` from
  jasalt/jolt-android-experiment, carried byte-identical with their sha256
  verified. Ten are ports from jlt-commons/raylib-jlt.
- **Two-level navigation.** `poc.raylib.gallery-ui` fits every card on one
  screen by dividing the height by the row count, which is unreadable past a
  handful. Categories sit above the pure contract instead, reusing
  `gallery-layout` with a different id list, so that file stays byte-identical.
- **A live seam.** `raylib.host/state` reads what the running scene holds,
  `on-next-frame!` queues work onto the main thread, and
  `raylib.gallery/tap!` injects a synthetic tap, so an editor can drive the app
  without a finger.
- **cider-nrepl**, opt-in behind `-A:cider`. The default build has no
  dependencies at all and that is worth keeping.
- **Capture tooling**, since moved out to a separate capture project so the
  next iOS app can reuse it. Every image in `docs/images` was taken off a real
  device by it, unattended, and Flappy Bird plays itself for the camera,
  flapped by a loop running inside the app.
- **Two guides.** `performance-on-a-phone.md` and `porting-an-example.md`.

### Fixed

- **`GetFPS` was being misread, not misbehaving.** It is a per-frame sampler:
  each call advances a 30-slot ring by one, so calling it from a 300-frame
  summary returns `1/(n * frame-time/30)` and decays toward the truth. The host
  computes its own rate from frame times now. Documented upstream in
  raysan5/raylib#6120.
- **Draw loops rewritten as indexed loops.** `partition` and `map-indexed` per
  frame cost three to four times what the FFI calls they fed did. spirograph
  went from 14 fps to 52 at the same point count, drawing the same lines.
- **A `safe-area-top` that could never work.** `SDL_GetDisplayUsableBounds`
  returns `uiscreen.bounds` on iOS and knows nothing of safe areas, so it
  always answered 0 against a real 62 pt inset. Removed; scenes ask UIKit.

### Upstream

- **jolt-lang/jolt#829, merged.** `sa-os-family` called a native iOS build
  Linux, so `tarm64ios` took Linux's `SIGCHLD`, `EAGAIN`, `O_NONBLOCK` and
  `struct stat` offsets on a Darwin system. The maintainer extended the fix to
  `build.ss`'s own `bld-tgt-osx?`.
- **raysan5/raylib#6120, open.** Documents that `GetFPS` must be called every
  frame.

### Not filed

- **raylib's SDL platform binding no framebuffer.** The code reading is correct
  and the conclusion drawn from it is not: measured on a device, both the
  drawable framebuffer and the colour renderbuffer are already bound at swap
  time whether or not this host binds anything. The report was written and
  withdrawn before filing. See `docs/guide/performance-on-a-phone.md`.
