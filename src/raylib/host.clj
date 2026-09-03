(ns raylib.host
  "The Android owner loop for raylib.

  raylib's Android backend IS the platform layer, so there is no SDL here.
  `rcore_android.c` defines `android_main`, which stores the NativeActivity's
  `android_app` and then calls `main(1, {\"raylib\"})` — the pinned source says
  so at lines 318-331, and that C main is
  `tools/android/app/src/main/cpp/main.c`. It dlopens this library, calls
  `jolt_library_init`, looks up the export at the bottom of an entry namespace
  and calls it. So the loop below runs on the thread `android_main` was handed,
  which is the thread raylib polls its ALooper on and the only one raylib or
  GLES may be touched from.

  Returning from that export returns from `main()`, and `android_main` then
  calls `ANativeActivity_finish` — which is what `finish!` is for, and why Back
  at the top of the gallery ends the activity.

  Two things this host deliberately does not do. There is no framebuffer
  juggling: raylib owns the EGL window surface, renders into framebuffer 0 and
  that framebuffer is real, so nothing has to be re-bound around a frame. And
  there is no safe-area query: the manifest asks for the fullscreen theme and
  deliberately does not opt into `shortEdges`, so under the default cutout mode
  Android lays the window out clear of the cutout and `:inset-top` is honestly
  0.

  `InitWindow(0, 0, title)` sizes the screen to the native window in PHYSICAL
  PIXELS — `SetupFramebuffer` copies the display size over a zero screen size,
  leaves render equal to screen and both offsets at 0 — so nothing scales."
  (:refer-clojure :exclude [run!])          ; run! is the entry point here, as in raylib-jlt
  (:require [clojure.string :as str]
            [jolt.ffi :as ffi]
            [raylib.probe :as probe]))

;; --- raylib: window, frame, drawing (the raylib-jlt subset, packed :uint colours) ---
(ffi/defcfn set-config-flags    "SetConfigFlags"    [:uint] :void)
(ffi/defcfn init-window         "InitWindow"        [:int :int :string] :void)
(ffi/defcfn window-should-close "WindowShouldClose" [] :uint8)
(ffi/defcfn close-window        "CloseWindow"       [] :void)
(ffi/defcfn set-target-fps      "SetTargetFPS"      [:int] :void)
(ffi/defcfn begin-drawing       "BeginDrawing"      [] :void)
(ffi/defcfn end-drawing         "EndDrawing"        [] :void)
(ffi/defcfn clear-background    "ClearBackground"   [:uint] :void)
(ffi/defcfn draw-text           "DrawText"          [:string :int :int :int :uint] :void)
(ffi/defcfn draw-circle         "DrawCircle"        [:int :int :float :uint] :void)
(ffi/defcfn draw-circle-lines   "DrawCircleLines"   [:int :int :float :uint] :void)
(ffi/defcfn draw-rectangle      "DrawRectangle"     [:int :int :int :int :uint] :void)
(ffi/defcfn draw-line           "DrawLine"          [:int :int :int :int :uint] :void)
(ffi/defcfn get-screen-width    "GetScreenWidth"    [] :int)
(ffi/defcfn get-screen-height   "GetScreenHeight"   [] :int)
(ffi/defcfn get-render-width    "GetRenderWidth"    [] :int)
(ffi/defcfn get-render-height   "GetRenderHeight"   [] :int)
(ffi/defcfn get-frame-time      "GetFrameTime"      [] :float)
(ffi/defcfn get-fps             "GetFPS"            [] :int)
(ffi/defcfn measure-text        "MeasureText"       [:string :int] :int)

;; rlgl immediate mode, for filling polygons raylib's shapes API has no call
;; for. All four are scalar, so they need none of the by-value machinery.
(ffi/defcfn rl-begin            "rlBegin"           [:int] :void)
(ffi/defcfn rl-end              "rlEnd"             [] :void)
(ffi/defcfn rl-vertex-2f        "rlVertex2f"        [:float :float] :void)
(ffi/defcfn rl-color-4ub        "rlColor4ub"        [:uint8 :uint8 :uint8 :uint8] :void)
(def RL-TRIANGLES 0x0004)

;; --- logcat ------------------------------------------------------------------
;; An Android app's stdout goes to /dev/null, so `println` from inside the app
;; writes into nothing: every diagnostic in this project goes through `log`
;; instead. `__android_log_write` lives in liblog.so, which is a DT_NEEDED of
;; libmain.so, so it resolves through the same handle raylib does — see the
;; :jolt/native note in deps.edn.
;;
;; `adb shell setprop log.redirect-stdio true` sends stray printlns to logcat
;; too, process-wide and until reboot. Handy while debugging; not something to
;; rely on, since it is off on any device that has not been told otherwise.
(ffi/defcfn ^:private android-log-write "__android_log_write" [:int :string :string] :int)
(def ^:private ANDROID-LOG-INFO 4)
(def LOG-TAG
  "The logcat tag every line from this app carries. `jolt log` filters on it."
  "raylib-android")

(defn log
  "One line to logcat, under LOG-TAG. The Android replacement for println: an
  app's stdout is discarded, so anything printed is simply lost."
  [& xs]
  (android-log-write ANDROID-LOG-INFO LOG-TAG (str/join " " (map str xs)))
  nil)

;; --- raylib: touch (RAY-010's scalar surface, plus the by-value Vector2) ----
(ffi/defcfn get-touch-point-count "GetTouchPointCount" [] :int)
(ffi/defcfn get-touch-point-id    "GetTouchPointId"    [:int] :int)
(ffi/defcfn get-touch-x           "GetTouchX"          [] :int)
(ffi/defcfn get-touch-y           "GetTouchY"          [] :int)
(ffi/defcfn get-touch-position    "GetTouchPosition"   [:int] [:by-value [:struct [[:x :float] [:y :float]]]])
(def ^:private vec2-l (ffi/layout [:struct [[:x :float] [:y :float]]]))
(defn touch-position
  "[x y] of touch point `i`, through the by-value Vector2 return."
  [i]
  (ffi/with-layout [v vec2-l]
    (get-touch-position v i)
    [(ffi/read-field v vec2-l :x) (ffi/read-field v vec2-l :y)]))

;; --- the hardware Back button ------------------------------------------------
;; raylib maps AKEYCODE_BACK to KEY_BACK (4) and registers the key state before
;; deciding what to do with the event; what it then does is EAT it — the pinned
;; rcore_android.c returns 1 for AKEYCODE_BACK "and don't let to be handled by
;; OS". So Back never reaches Android, never sets shouldClose, and is entirely
;; ours: IsKeyPressed(KEY_BACK) is the whole story, and an app that wants Back
;; to leave has to call finish! itself.
(ffi/defcfn ^:private is-key-pressed "IsKeyPressed" [:int] :uint8)
(def KEY-BACK 4)

(defn back-pressed?
  "Did the hardware/gesture Back fire this frame?"
  []
  (pos? (is-key-pressed KEY-BACK)))

(defn rgba [r g b a] (bit-or r (bit-shift-left g 8) (bit-shift-left b 16) (bit-shift-left a 24)))
(def RAYWHITE  (rgba 245 245 245 255))
(def LIGHTGRAY (rgba 200 200 200 255))
(def DARKGRAY  (rgba 80 80 80 255))
(def MAROON    (rgba 190 33 55 255))
(def SKYBLUE   (rgba 102 191 255 255))

;; --- the display -------------------------------------------------------------
(ffi/defcfn ^:private get-monitor-physical-width "GetMonitorPhysicalWidth" [:int] :int)
(def ^:private BASE-DPI 160.0)              ; Android's 1x density bucket

(defn- density-scale
  "The display's density multiplier, recovered from raylib's own
  AConfiguration_getDensity.

  raylib does not expose the density on Android and GetWindowScaleDPI answers
  1.0 there, but GetMonitorPhysicalWidth gives it away: the pinned source
  computes it as (widthPixels/dpi)*25.4, so dividing the pixel width back by
  the millimetre width recovers the dpi to within that call's integer
  truncation. 1080 px over 57 mm gives 481 where the device reports 480, and
  rounding to sixteenths lands on 3.0 — which is all a scale is used for here,
  namely font and stroke sizes.

  A density of 0 (ACONFIGURATION_DENSITY_NONE) divides by zero inside raylib
  and comes back as nonsense, so an implausible answer falls back to the pixel
  width against a nominal 400-unit-wide phone rather than trusting it."
  [width]
  (let [mm (get-monitor-physical-width 0)
        k  (when (pos? mm)
             (/ (double (int (+ 0.5 (* 16.0 (/ (* width 25.4) mm BASE-DPI))))) 16.0))]
    (if (and k (<= 0.75 k 6.0))
      k
      (let [fallback (max 1.0 (/ width 400.0))]
        (log "no usable display density (physical width" mm "mm), scale falls back to" fallback)
        fallback))))

;; --- the host ----------------------------------------------------------------
;; The scene map run! was handed: {:title :init :frame :fps}. There for an
;; nREPL to look at, since the loop otherwise keeps it in a local. defonce
;; takes no docstring, unlike def, hence the comment.
(defonce running-scene (atom nil))

;; --- the live seam (raylib.live, an nREPL) -----------------------------------
;; An nREPL eval runs on jolt.nrepl's accept thread, and raylib is affine to
;; the thread android_main handed us: calling DrawCircle or InitWindow from an
;; eval is a crash waiting for a race rather than a working REPL. And the
;; scene's state is threaded through the loop below, so there is nothing global
;; for an editor to look at either.
;;
;; Two small things fix both. `state` is refreshed every frame, so an eval can
;; read what the scene currently holds. `on-next-frame!` queues a thunk that
;; the loop runs on the owner thread, between BeginDrawing and the scene's own
;; frame fn, which is the only safe place to touch raylib from outside.
;;
;; The drain is swap-vals! rather than deref-then-reset!: a thunk posted
;; between the read and the clear would otherwise be captured by neither, and
;; vanish with no error and no log line.

(defonce ^:private current-state (atom nil))
(defonce ^:private pending (atom []))
(defonce ^:private finish? (atom false))

(defn state
  "Whatever the running scene's frame fn returned last. nil before the first
  frame. Read-only: reset!ing this does not affect the loop, which threads its
  own state through recur."
  []
  @current-state)

(defn on-next-frame!
  "Queue zero-arg `f` to run on the owner thread at the top of the next frame.
  The only safe way to call raylib from an nREPL eval. Exceptions are logged
  rather than thrown, so a bad thunk cannot take the loop down."
  [f]
  (swap! pending conj f)
  nil)

(defn finish!
  "Ask the owner loop to return after this frame, which returns from main() and
  lets android_main call ANativeActivity_finish — i.e. quits the app. Back at
  the top of the gallery calls this."
  []
  (reset! finish? true)
  nil)

(defn- drain-pending! []
  (let [[queued _] (swap-vals! pending (constantly []))]
    (doseq [f queued]
      (try (f)
           (catch :default e (log "queued work failed:" (ex-message e)))))))

(defn run!
  "Own the frame loop for `scene` until Back or Android ends it, and return the
  number of frames drawn (which is what the C host reports as its exit status).

  scene: {:title s, :init (fn [{:keys [width height scale inset-top]}] state),
          :frame (fn [state] state'), :fps n}

  An escaping exception is logged and answered with -1 rather than left to
  unwind into `android_main`, because a Chez error reaching C takes the process
  down with nothing in logcat to say why."
  [scene]
  (reset! running-scene scene)
  (reset! finish? false)
  (let [{:keys [title init frame fps] :or {title "raylib" fps 60}} scene]
    (init-window 0 0 title)
    (set-target-fps fps)
    (let [w (get-screen-width)
          h (get-screen-height)
          k (density-scale w)]
      (log "screen" w "x" h "px, render" (get-render-width) "x" (get-render-height)
           "density scale" k "— target" fps "fps")
      (try
        ;; milestone 5's numbers: every 300 frames, the mean and worst frame time
        (loop [state (init {:width w :height h :scale k :inset-top 0}) n 0 sum 0.0 worst 0.0]
          (begin-drawing)
          (drain-pending!)                    ; owner thread, inside the frame
          (let [state' (frame state)]
            (reset! current-state state')
            (when @probe/fps-every-frame? (reset! probe/last-fps (get-fps)))
            (end-drawing)
            (let [dt    (get-frame-time)
                  n     (inc n)
                  sum   (+ sum dt)
                  worst (max worst dt)]
              ;; fps from this window's own frame times, never from GetFPS:
              ;; sum is 300 frame times in seconds, so 300/sum is exactly the
              ;; window's rate. GetFPS is a per-frame sampler and reading it
              ;; from a 300-frame summary returns nonsense; see the README.
              (when (zero? (mod n 300))
                (log (format "%d frames, mean %.2f ms, worst %.1f ms, %.1f fps"
                             n (* 1000.0 (/ sum 300)) (* 1000.0 worst) (/ 300.0 sum))))
              (if (or @finish? (pos? (window-should-close)))
                (do (log "leaving the loop after" n "frames"
                         (if @finish? "(finish! was called)" "(Android asked the window to close)"))
                    n)
                (recur state' n
                       (if (zero? (mod n 300)) 0.0 sum)
                       (if (zero? (mod n 300)) 0.0 worst))))))
        (catch :default e
          (log "the loop failed:" (ex-message e) (pr-str (ex-data e)))
          -1)
        (finally
          (close-window))))))
