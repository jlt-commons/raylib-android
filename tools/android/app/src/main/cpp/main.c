/* main.c: the NativeActivity entry point, and the only C this project has.
 *
 * raylib's Android backend owns the activity. rcore_android.c declares
 * `extern int main(int argc, char *argv[])`, and its android_main stores the
 * android_app, calls main(1, {"raylib"}), and then calls
 * ANativeActivity_finish -- so this function IS the app's lifetime, and
 * returning from it quits.
 *
 * All it does is bootstrap Jolt: dlopen the cross-compiled library, call
 * jolt_library_init, resolve one export through jolt_lookup and call it. That
 * export is the frame loop (raylib.host/run!), which therefore runs on this
 * thread -- the one android_main handed us, which is the thread raylib polls
 * its ALooper on and the only one that may touch raylib or GLES.
 *
 * raylib itself is linked STATICALLY into this library, so every raylib symbol
 * a defcfn names is already in the image: the Jolt library resolves them by
 * dlopening "libmain.so", which is this. See the :jolt/native note in
 * deps.edn.
 *
 * Everything here is logged, because an Android app's stdout goes nowhere and
 * a failure between dlopen and the first frame is otherwise a blank screen.
 */
#include <android/log.h>
#include <dlfcn.h>
#include <stddef.h>
#include <sys/types.h>
#include <unistd.h>

#define LOG_TAG "raylib-android"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* The jolt --library ABI: three C entry points every built library exports. */
typedef int (*jolt_init_fn)(int, char **);
typedef void *(*jolt_lookup_fn)(const char *);
typedef void (*jolt_shutdown_fn)(void);

/* What an entry namespace publishes with (ffi/export! "raylib_main" run [] :int):
 * the owner loop, answering the number of frames it drew. */
typedef int (*entry_fn)(void);

#define JOLT_LIBRARY "libjoltraylib.so"
#define ENTRY_RELEASE "raylib_main"
#define ENTRY_DEBUG "raylib_main_debug"

int main(int argc, char *argv[]) {
  pid_t owner = gettid();
#ifdef NDEBUG
  const char *want = ENTRY_RELEASE;
  const char *mode = "release";
  const char *entry_ns = "raylib.gallery";
#else
  const char *want = ENTRY_DEBUG;
  const char *mode = "debug";
  const char *entry_ns = "raylib.live";
#endif
  LOGI("enter main mode=%s owner-thread=%d", mode, owner);

  void *library = dlopen(JOLT_LIBRARY, RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    LOGE("dlopen %s failed: %s", JOLT_LIBRARY, dlerror());
    return 1;
  }

  jolt_init_fn init = (jolt_init_fn)dlsym(library, "jolt_library_init");
  jolt_lookup_fn lookup = (jolt_lookup_fn)dlsym(library, "jolt_lookup");
  jolt_shutdown_fn shutdown =
      (jolt_shutdown_fn)dlsym(library, "jolt_library_shutdown");
  if (!init || !lookup || !shutdown) {
    LOGE("the jolt library ABI is not in %s: %s", JOLT_LIBRARY, dlerror());
    dlclose(library);
    return 2;
  }

  int initialized = init(argc, argv);
  LOGI("jolt_library_init=%d", initialized);
  if (initialized != 0) {
    dlclose(library);
    return 3;
  }

#ifdef NDEBUG
  /* A release image must not contain the debug entry, because that entry is
   * the one that starts an nREPL. Refusing here means a release APK built by
   * mistake from raylib.live fails loudly at launch instead of shipping a
   * listener. The debug build makes no symmetric demand: its image contains
   * both exports, since raylib.live requires raylib.gallery. */
  if (lookup(ENTRY_DEBUG) != NULL) {
    LOGE("release image exports %s; refusing to run a debug entry point",
         ENTRY_DEBUG);
    shutdown();
    dlclose(library);
    return 4;
  }
#endif

  entry_fn entry = (entry_fn)lookup(want);
  LOGI("jolt_lookup %s=%s", want, entry ? "ok" : "missing");
#ifndef NDEBUG
  /* A debug APK built from an entry namespace that publishes no debug export
   * -- raylib.touch, say, or raylib.flappy -- still runs. Only the release
   * direction is a refusal, because only that direction risks shipping a
   * listener. */
  if (!entry) {
    entry = (entry_fn)lookup(ENTRY_RELEASE);
    if (entry) {
      LOGI("no %s in this image; falling back to %s (an entry namespace "
           "without an nREPL)",
           ENTRY_DEBUG, ENTRY_RELEASE);
      want = ENTRY_RELEASE;
    }
  }
#endif
  if (!entry) {
    LOGE("no %s in %s: build it with NS=%s", want, JOLT_LIBRARY, entry_ns);
    shutdown();
    dlclose(library);
    return 5;
  }

  LOGI("calling %s on thread=%d", want, gettid());
  int frames = entry();
  LOGI("%s returned frames=%d", want, frames);

  shutdown();
  LOGI("jolt_library_shutdown done; returning from main so android_main can "
       "finish the activity");
  dlclose(library);
  return frames > 0 ? 0 : 6;
}
