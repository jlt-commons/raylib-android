# RUNBOOK

Operating this project: first-time setup, the daily loop, live development, and
the failures you will actually hit.

> **This port has not yet been run on hardware.** The iOS runbook this file
> replaces recorded only things that had been done; every step below is either
> derived from the pinned raylib source (cited where it matters) or taken from
> [jasalt/jolt-android-experiment](https://github.com/jasalt/jolt-android-experiment),
> which proved this exact recipe — Chez cross-built for Bionic, `jolt build
> --library`, a NativeActivity C `main` that dlopens it — on an API 35 device.
> What is unproven here is *this* tree on *your* phone. Treat the numbers in
> the README's performance guide as iPhone measurements until they are taken
> again.

## What you need

- **JDK 17** and **Gradle 8.9 or newer** on `PATH` (AGP 8.7 requires both).
- The **Android SDK** with platform 35 and platform-tools. `ANDROID_HOME`, or
  the usual `~/Android/Sdk`.
- An **NDK**. Any recent one; `ANDROID_NDK_ROOT` wins, otherwise the newest
  under `$ANDROID_HOME/ndk` is used, and whichever is chosen is passed to both
  Gradle and the Chez cross-build so they cannot disagree.
- **An arm64 device.** The APK carries one ABI. `jolt devices` says plainly
  whether a device can run it; an x86_64 emulator without ARM64 translation
  installs it and then fails to load `libmain.so`.
- An x86_64 Linux box or an Apple Silicon Mac to *build* on. `pack.sh` refuses
  to run on arm64 Linux and says why: Chez has one machine type for both sides
  of that cross, so the host build and the Android build would overwrite each
  other.

## First time

```sh
jolt test                     # 35 tests, 275 assertions, no device needed
sh tools/android/deps.sh      # the pinned raylib source, ~20 MB, once
sh tools/android/pack.sh      # ChezScheme, cross-built for Bionic. ~15 minutes
jolt devices                  # what is connected, and whether it is arm64
```

`deps.sh` only downloads. Nothing cross-builds raylib here, unlike the iOS
recipe: raylib has a real Android backend, so the APK's own CMake compiles
`rcore_android.c` straight into `libmain.so`.

`pack.sh` is the slow one and the interesting one. It builds a host Chez, then
`make bootquick XM=tarm64le` for the target's boot files and the cross
`xpatch`, then the C kernel again with the NDK's clang, `-fPIC`, and
`--disable-iconv` (Bionic has no iconv, and Chez's kernel is the one place that
asks for it). It caches in `~/.cache/raylib-android` and is a no-op afterwards.

## The loop

```sh
jolt build-app                # debug: raylib.live, --dev, with an nREPL
jolt deploy                   # adb install, force-stop, am start
jolt log                      # everything the app says
```

```sh
jolt release                    # raylib.gallery: no listener, no INTERNET permission
NS=raylib.touch jolt build-app  # a smoke entry, one screen of touch state
NS=raylib.flappy jolt build-app

# A jolt task takes no arguments, so `jolt build-app release` runs build.sh
# with none and builds DEBUG. The release task above, or MODE=release, is how
# to ask for the other variant -- and MODE works on jolt deploy too.
```

Namespaces worth building: `raylib.touch` (is anything alive), `raylib.flappy`,
`raylib.gallery`, `raylib.live`.

**There is no console.** An Android app's stdout goes to `/dev/null`, so
`println` writes into nothing and every diagnostic in this project goes through
`raylib.host/log`, which calls `__android_log_write`. `jolt log` is where it
lands, along with raylib's own `TRACELOG` under the `raylib` tag and a
tombstone under `DEBUG` if the process dies. If you want stray `println`s too:
`adb shell setprop log.redirect-stdio true`, which is process-wide and lasts
until reboot.

## Live development

```sh
jolt live                                    # builds raylib.live, installs, forwards
tools/android/nrepl eval 7888 '(System/getProperty "os.arch")'
tools/android/nrepl repl 7888                # or a prompt
```

Unlike the iOS `iproxy` this replaces, `adb forward` installs a rule in the adb
server and returns — there is nothing to leave running in another terminal, and
the rule lasts until the device disconnects or `sh tools/android/proxy.sh
remove`.

`LOCAL_PORT` moves this machine's end. The device's end is fixed at 7888
(`raylib.live/nrepl-port`): an Android app inherits no environment and Intent
extras do not reach a NativeActivity's C `main`, so there is nowhere for a port
to arrive from.

**Prove you are talking to the phone before believing an answer.** Ask for
`os.arch`: the device says `aarch64` and an `x86_64` answer is a process on
this machine. See "An eval answered, and it was the wrong machine" below, which
happened on the iOS side of this project and cost an afternoon.

An eval runs on jolt.nrepl's accept thread while the owner thread is inside the
frame loop, and raylib belongs to that thread — `android_main` handed it over
and raylib polls its ALooper there. So:

```clojure
;; safe: the loop refreshes this every frame
(do (require '[raylib.host]) (raylib.host/state))

;; safe: runs at the top of the next frame, on the owner thread
(raylib.host/on-next-frame! (fn [] (raylib.host/set-target-fps 30)))

;; NOT safe: calls raylib from the nREPL thread
(raylib.host/set-target-fps 30)
```

### The debug build is `--dev`, and that is the point

`build.sh debug` passes `--dev`; release does not. This is the difference
between a REPL you can develop with and one you can only read with.

A release image inlines across call sites. A var redefined over the nREPL then
updates what the REPL itself sees while every already-compiled caller keeps
calling the original, and nothing announces the split. Measured on the iOS side
of this project, redefining `point` and asking `advance` (its caller in the same
namespace) what it returns:

| build | `advance` sees the redefinition |
|---|---|
| release | no |
| `--dev` | yes |

That covers plain `def` constants too: a release build will happily report
`max-points` as 600 while the running loop still uses 1800. The cost was close
to nothing for this workload — `--dev` held 58.5 fps against release's 58.8 on
an iPhone. Develop on debug, ship release.

### Driving the app from the REPL

Reading state is not enough to test a scene, because the scene state is
threaded through the loop rather than kept in an atom, so an editor can look and
not touch. `raylib.gallery/tap!` is the other half:

```clojure
;; open a card without a finger. Coordinates are screen pixels, which is the
;; only unit raylib deals in here.
(raylib.gallery/tap! 300 900)

;; where the cards actually are, asked of the running layout
(let [m {:screen [(rl/get-screen-width) (rl/get-screen-height)]}]
  (mapv (juxt :scene-id :x :y)
        (:cards (ui/gallery-layout m raylib.gallery/scene-ids (diag/layout m)))))

;; what the open scene is doing right now
(:scene-state (:gstate (raylib.host/state)))
```

One tap is consumed per frame and cleared as it is taken, so a queued tap cannot
be read twice and mistaken for a held touch.

An nREPL is a development feature only. Google Play's Device and Network Abuse
policy treats an app that fetches and runs executable code as a violation, so
the release variant carries no listener — and `main.c` refuses to run a release
image in which the nREPL entry point exists at all.

## When it goes wrong

**A black screen and nothing else.** `jolt log` first, always. The bootstrap in
`main.c` logs every step — `dlopen`, `jolt_library_init`, the `jolt_lookup` of
the entry symbol — so a failure between launch and the first frame names
itself. The most likely lines:

- `dlopen libjoltraylib.so failed` — the library was not staged into the APK.
  Rerun `jolt build-app`; it stages into `app/src/<variant>/jniLibs`.
- `jolt_lookup raylib_main_debug=missing` — the image was built from a
  namespace that publishes no debug export. A debug build falls back to
  `raylib_main` and logs that it did; a release build refuses.
- nothing at all under `raylib-android` — the activity never reached `main`.
  Look at `ActivityManager` and `DEBUG` in the same log.

**`java.lang.UnsatisfiedLinkError: dlopen failed: library "libmain.so" not
found`, or the app dies immediately on an emulator.** The APK is arm64-v8a
only. `jolt devices` prints each device's ABI list for this reason.

**`INSTALL_PARSE_FAILED_NO_CERTIFICATES`.** A release APK out of Gradle is
unsigned. `deploy.sh` refuses one by name rather than letting adb produce that
message; `build.sh` prints the two commands that sign it.

**The Chez cross-build fails on a Bionic symbol.** Raise `raylib.apiLevel` in
`tools/android/gradle.properties` and rerun `pack.sh` — the pack directory is
keyed by API level, so the old one is left alone. 26 is the floor chosen here;
35 is what the upstream experiment proved.

**`build.sh` says the target pack was not built for Android.** It read the
library's `DT_NEEDED` and found glibc's `libc.so.6` rather than Bionic's
`libc.so`. That means the pack in `~/.cache/raylib-android/pack/...` came from
an ordinary Linux cross-build. Delete it and rerun `pack.sh`.

**An eval answered, and it was the wrong machine.** On the iOS side a stray JVM
nREPL held the loopback port while the forwarder bound the IPv6 wildcard;
connections went to the JVM. The evals succeeded and returned entirely
plausible values which were simply the desktop's. Nothing failed and nothing
warned. `proxy.sh` now refuses to forward onto a listener that is not its own
and names it, but the habit that protects you is asking for `os.arch` first.

**Back does not leave a scene, or leaves the app instead.** Back is entirely
this app's to interpret: the pinned `rcore_android.c` eats `AKEYCODE_BACK`
("and don't let to be handled by OS") after recording the key state, so it
never reaches Android and never sets `shouldClose`. `raylib.gallery` reads it
as one level up — scene, then category list, then categories, then quit — and
quitting means returning from the loop, which returns from `main`, after which
`android_main` calls `ANativeActivity_finish`.

**`GetFPS` returns something absurd.** It is a stateful sampler that must be
called every frame; see the README. The host computes its own rate from
`GetFrameTime`, and scenes that draw `GetFPS` every frame are fine.

**A rotation or a screen lock restarts everything.** It should not: the
manifest declares `configChanges="orientation|screenSize|keyboardHidden"`,
which is the list `rcore_android.c`'s own comment asks for, and without it
locking the phone sends `CMD_TERM_WINDOW`/`CMD_DESTROY` and the Chez heap goes
with the activity. The activity is also fixed to portrait.

## Signing

Debug builds are signed with Gradle's debug keystore and install as they are.
Release builds come out unsigned; sign them with your own key, out of tree:

```sh
zipalign -f -p 4 tools/android/app/build/outputs/apk/release/app-release-unsigned.apk app-release.apk
apksigner sign --ks <keystore> --ks-key-alias <alias> app-release.apk
APK=app-release.apk MODE=release jolt deploy
```

Nothing about a keystore belongs in this repository, so nothing about one is
here.
