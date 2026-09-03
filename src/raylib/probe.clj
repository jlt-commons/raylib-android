(ns raylib.probe
  "The measuring apparatus, kept out of the owner loop.

  Everything here is off by default and exists to answer questions about what
  the device actually does, rather than what reading the source suggests it
  should. That distinction earned its own namespace on iOS, where this project
  spent a day believing raylib rendered into framebuffer 0 and the driver
  disagreed. On Android framebuffer 0 IS the EGL window surface and the
  question is settled — the report below asserts that rather than assuming it,
  because the assumption is exactly the one that was wrong last time.

  `raylib.host` requires this, reads the flags in its loop and fills in the
  atoms. The dependency runs host -> probe and never back, which is why the
  handful of FFI declarations below are duplicated from the host rather than
  shared: a defcfn is a Chez foreign-procedure resolved by symbol name at first
  call, so two declarations of glGetIntegerv are the same function, and paying
  that to keep the namespaces acyclic is a good trade.

  Nothing here runs at load."
  (:require [jolt.ffi :as ffi]))

;; --- the GL surface these probes need ---------------------------------------
(ffi/defcfn gl-check-framebuffer-status "glCheckFramebufferStatus" [:uint] :uint)
(ffi/defcfn gl-get-integerv             "glGetIntegerv"            [:uint :pointer] :void)
(ffi/defcfn gl-get-string               "glGetString"              [:uint] :string)

(def GL-FRAMEBUFFER 0x8D40)
(def GL-FRAMEBUFFER-BINDING 0x8CA6)
(def GL-RENDERBUFFER-BINDING 0x8CA7)
;; Anything other than this means the bound framebuffer is not a usable target.
(def GL-FRAMEBUFFER-COMPLETE 0x8CD5)
(def ^:private GL-VENDOR 0x1F00)
(def ^:private GL-RENDERER 0x1F01)
(def ^:private GL-VERSION 0x1F02)
(def ^:private GL-MAX-TEXTURE-SIZE 0x0D33)

(defn gl-int
  "One integer of GL state."
  [pname]
  (ffi/with-alloc [p 4] (gl-get-integerv pname p) (ffi/read p :int 0)))

;; --- the toggles -------------------------------------------------------------

;; GetFPS is a per-frame sampler: each call advances a 30-slot ring by one and
;; returns 1/sum-of-ring. With this on, the loop calls it every frame and parks
;; the answer in last-fps; with it off nothing calls it, so an nREPL can call it
;; at whatever cadence it likes and watch the ring fill. Both halves of that
;; experiment come from one APK.
(defonce fps-every-frame? (atom false))
(defonce last-fps (atom nil))

;; --- the reports -------------------------------------------------------------
;; Both MUST run on the owner thread: hand them to raylib.host/on-next-frame!.
;; GLES has one current context and it belongs to the thread android_main gave
;; us, so a query from an nREPL worker answers 0 for everything at best.

(defn framebuffer-report
  "What GL makes of the framebuffer raylib is drawing into, on this device.

  On Android this is expected to be plain: bound is 0 and the status is 36053
  (GL_FRAMEBUFFER_COMPLETE), because framebuffer 0 is the EGL window surface
  and it exists. An iPhone answers 33305 (GL_FRAMEBUFFER_UNDEFINED) for the
  same query, which is the difference this port removed a hundred lines of
  framebuffer juggling over."
  []
  {:framebuffer  (gl-int GL-FRAMEBUFFER-BINDING)
   :renderbuffer (gl-int GL-RENDERBUFFER-BINDING)
   :status       (gl-check-framebuffer-status GL-FRAMEBUFFER)
   :complete     GL-FRAMEBUFFER-COMPLETE})

(defn gl-report
  "Which GLES driver this is. Worth asking on a phone whose GPU you did not
  choose, and the answer explains most performance surprises."
  []
  {:vendor           (gl-get-string GL-VENDOR)
   :renderer         (gl-get-string GL-RENDERER)
   :version          (gl-get-string GL-VERSION)
   :max-texture-size (gl-int GL-MAX-TEXTURE-SIZE)})
