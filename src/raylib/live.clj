(ns raylib.live
  "The gallery with an nREPL listening, so a running app on the phone can be
  inspected and driven from an editor.

  Debug only, and structurally so. Google Play's Device and Network Abuse
  policy treats an app that fetches and runs executable code as a violation,
  and an nREPL is exactly that — so this namespace is the entry point of the
  DEBUG build alone. The release APK is built from raylib.gallery, whose image
  carries no listener at all, and `tools/android/app/src/main/cpp/main.c` refuses
  to run a release build in which the debug export exists. The debug
  `AndroidManifest.xml` is also the only one that asks for INTERNET.

  jolt.nrepl binds loopback, so reaching it means forwarding a port over adb:

      NS=raylib.live sh tools/android/build.sh debug
      sh tools/android/deploy.sh
      jolt proxy                                  # adb forward, in another terminal
      tools/android/nrepl eval 7888 '(raylib.host/state)'

  An eval runs on jolt.nrepl's accept thread while the owner thread is inside
  the frame loop, and raylib is affine to that thread. So read freely, and put
  anything that touches raylib through raylib.host/on-next-frame!, which runs
  it at the top of the next frame:

      ;; safe: reads a value the loop refreshes every frame
      (:gstate (raylib.host/state))

      ;; safe: runs on the owner thread, inside the frame
      (raylib.host/on-next-frame! #(raylib.host/set-target-fps 30))

      ;; NOT safe: calls raylib from the nREPL thread
      (raylib.host/set-target-fps 30)"
  (:require [jolt.ffi :as ffi]
            [jolt.nrepl]
            [raylib.gallery :as gallery]
            [raylib.host :as rl]))

(def nrepl-port
  "The phone's own loopback port, forwarded to this machine by `jolt proxy`.
  7888 by convention, matching the notebooks and the Android experiment.

  Fixed rather than configurable: an Android app inherits no shell environment
  and an activity's Intent extras do not reach a NativeActivity's C main, so
  there is nowhere for a port to arrive from. Change it here and rebuild."
  7888)

(defn start-nrepl!
  "Start the nREPL, optionally composing `middleware` over jolt.nrepl's built-in
  handler. nil means the built-in ops alone, which is what this namespace uses
  and what keeps the default build free of dependencies.

  A failure is reported and swallowed on purpose: losing the whole app because
  a REPL could not bind would be a poor trade, and the gallery is still worth
  looking at without one."
  [middleware]
  (try
    (if (seq middleware)
      (jolt.nrepl/start nrepl-port middleware)
      (jolt.nrepl/start nrepl-port))
    (rl/log "live: nREPL on the phone's 127.0.0.1:" nrepl-port
            (if (seq middleware) "(with middleware)" "(built-in ops)")
            "- forward it with: jolt proxy")
    (catch :default e
      (rl/log "live: jolt.nrepl/start failed:" (ex-message e))
      (rl/log "live: continuing without a REPL; the gallery still runs"))))

(defn run
  "The gallery, with a listener in front of it. Returns the frame count."
  []
  ;; Logged rather than assumed. jolt picks its socket constants and sockaddr
  ;; layout from os.name, and on Android the right answer is "Linux" — Bionic
  ;; is close enough to glibc for jolt.nrepl's sockets. When that answer was
  ;; wrong on iOS (before 0.8.0), socket() came back EINVAL and
  ;; jolt.nrepl/start died with "socket() failed". If that line ever appears in
  ;; logcat, this is the first thing to check.
  (rl/log "live: os.name" (pr-str (System/getProperty "os.name"))
          "os.arch" (pr-str (System/getProperty "os.arch")))
  (start-nrepl! nil)
  (gallery/run))

(defn -main [& _] (run))

;; The debug export. main.c looks this up when NDEBUG is not defined, and
;; asserts it is ABSENT from a release image — so a release APK cannot
;; accidentally be built from this namespace and ship a listener.
(ffi/export! "raylib_main_debug" run [] :int)
