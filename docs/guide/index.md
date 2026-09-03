# raylib-android

raylib rendering on a physical Android phone, driven from Clojure running on
Chez Scheme via [Jolt](https://github.com/jolt-lang/jolt). Seventeen scenes in
a NativeActivity, as native arm64 code, with no JVM, no Kotlin and no Java
anywhere in the app.

This is the orientation page. The two guides after it are the ones worth
reading, and both are about things the device taught us rather than things the
code implied. Both were written on the
[iOS sibling](https://github.com/jlt-commons/raylib-ios) of this project, whose
numbers they quote; the scenes are the same files, and this host has not yet
been measured on Android.

## Why this works at all

Two facts do most of the work, and neither is obvious.

**raylib's Android backend asks for one C function.**
`src/platforms/rcore_android.c` is a real platform layer — EGL, GLES2, touch,
the lifecycle, the ALooper pump — and what it wants from an app is
`extern int main(int, char **)`. `android_main` stores the `android_app`, calls
that `main`, and then calls `ANativeActivity_finish`. So the app's whole
lifetime is one C function, and returning from it quits.

**A Jolt library is a shared object with a C ABI.** `jolt build --library`
emits `jolt_library_init`, `jolt_lookup` and `jolt_library_shutdown`, and
`ffi/export!` publishes a Clojure function under a C-callable name. So the C
`main` above is twenty lines: dlopen, init, look up the frame loop, call it.
Unlike the iOS sibling — where Apple forbids generating code at run time, so
the app had to be threaded portable bytecode — this is native arm64.

## Who owns the owner thread

This is the whole design, and it is the question every attempt at this founders
on.

raylib and GLES may only be touched from the thread `android_main` runs on:
that is where the EGL context is current and where the ALooper is pumped. The
chain from the activity to the Clojure loop never leaves it —
`NativeActivity` → `android_main` → our `main` → `jolt_lookup` →
`raylib.host/run!` — so the loop inherits the right thread by construction
rather than by hopping onto it.

Nothing here needs a run-loop-friendly loop shape, either, which is the other
half of what the iOS host had to prove: there a blocking `while` loop starves
the run loop that delivers touches, and it was only legal because `EndDrawing`
reaches `SDL_PumpEvents` through three intervening functions. On Android
`EndDrawing` polls the ALooper directly, in `PollInputEvents`, on this thread.

The one thing that does leave the thread is an nREPL eval, which lands on
jolt.nrepl's accept thread. So reads are free and anything calling raylib goes
through `raylib.host/on-next-frame!`, a queue the loop drains at the top of a
frame.

## The scene contract

Every scene is a reducer over frames:

```clojure
{:id :lorenz :title "Lorenz"
 :init    (fn [input]        [state events])
 :update  (fn [state input]  [state events])
 :draw    (fn [state input]  [state events])
 :dispose (fn [state]        [state events])}
```

No raylib call appears anywhere in it. Drawing is a separate multimethod that
reads the state a scene produced, which is why the scenes are pure `.cljc` and
test on a build host with no raylib, no NDK and no device.

That separation is not tidiness. Three of the scenes came from the
[Jolt Android experiment](https://github.com/jasalt/jolt-android-experiment)
byte-identical, sha256 verified, along with three more namespaces carrying the
contract itself. They were written for a different platform and run here
untouched. The other fourteen are ports from
[raylib-jlt](https://github.com/jlt-commons/raylib-jlt).

## The two guides

**[Performance on a phone](performance-on-a-phone.html)** is the one to read
first. It starts with a wrong guess, that the FFI boundary was the cost, and
follows the measurements to what it actually was. One scene makes about 2400
calls into C every frame at 59 fps while another drawing 1800 lines managed 18.
The answer was allocation in the draw loop. It also covers why `GetFPS` returns
a plausible wrong number when you call it the obvious way, why primitive count
is a proxy rather than a budget, and why a reading past the knee is not
repeatable.

**[Porting an example](porting-an-example.html)** is the practical one: taking a
raylib-jlt example that owns its own loop and turning it into a scene that does
not. Inverting the loop, replacing `GetRandomValue` with a seeded generator so
a scene replays identically, deriving geometry from the live screen instead of a
fixed 800x450, and moving drawing to the caller.

## Getting it running

The README covers the build in full. The short version:

```sh
sh tools/android/deps.sh                          # the pinned raylib source
sh tools/android/pack.sh                          # Chez for Bionic. once, ~15 min
NS=raylib.gallery sh tools/android/build.sh release
sh tools/android/deploy.sh release
```

`tools/android/RUNBOOK.md` has the failure modes, including the six traps worth
knowing before the first build, and `jolt log` is where the app speaks — an
Android app's stdout goes nowhere, so every diagnostic is a logcat line.

For a REPL inside the running app, `tools/android/live.sh` builds the debug
variant with `jolt.nrepl` and forwards its port over adb. Reading live scene
state from an editor is how most of the measurements in the performance guide
were taken. One trap: a release build inlines across call sites, so redefining
a var updates what the REPL sees while the running loop keeps calling the
original. The debug build is `--dev` for exactly that reason.
