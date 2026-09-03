cmake_minimum_required(VERSION 3.22.1)
project(raylib_android C)

# RAYLIB_SOURCE is the pinned raylib tree tools/android/deps.sh downloaded, and
# build.gradle.kts passes it in from $RAYLIB_SOURCE (or -Praylib.source). It is
# a CMake argument rather than an environment read so that changing it
# re-configures instead of silently reusing a cached build.
if(NOT RAYLIB_SOURCE)
  message(FATAL_ERROR
    "RAYLIB_SOURCE is not set. Run `sh tools/android/deps.sh` and build "
    "through `sh tools/android/build.sh`, which exports it.")
endif()
if(NOT EXISTS "${RAYLIB_SOURCE}/src/rcore.c")
  message(FATAL_ERROR "RAYLIB_SOURCE does not look like a raylib tree: ${RAYLIB_SOURCE}")
endif()

# PLATFORM=Android is forced here rather than passed per-invocation: it is not
# a choice this project makes twice. It selects rcore_android.c, pins
# GRAPHICS_API_OPENGL_ES2, and pulls android_native_app_glue.c out of the NDK
# that Gradle's toolchain file points ANDROID_NDK at.
set(PLATFORM "Android" CACHE STRING "raylib platform backend" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "raylib as a static archive" FORCE)

list(APPEND CMAKE_MODULE_PATH "${RAYLIB_SOURCE}/cmake")
# Only src/, so raylib's examples and install rules never enter this build.
add_subdirectory("${RAYLIB_SOURCE}/src" raylib-build EXCLUDE_FROM_ALL)

# libmain.so, which is what the manifest's android.app.lib_name names. raylib
# is linked into it statically, so the Jolt library's defcfns resolve against
# this image -- see the :jolt/native note in deps.edn.
add_library(main SHARED main.c)
target_include_directories(main PRIVATE "${RAYLIB_SOURCE}/src")

# The activity's own entry point. raylib defines ANativeActivity_onCreate (in
# the NDK glue it compiles in), but nothing in main.c references it, so without
# -u the linker drops it from a static archive and Android reports
# "Unable to find native library entry point". raylib sets this flag for its
# own shared-library link; add_subdirectory does not export a subdirectory's
# CMAKE_SHARED_LINKER_FLAGS to this scope, so it has to be repeated here.
#
# -Wl,--wrap=fopen arrives on its own: raylib declares it PUBLIC, so
# target_link_libraries propagates it to this final link, which is where APK
# asset wrapping has to happen. This app opens no assets, and gets it anyway.
target_link_options(main PRIVATE "-u" "ANativeActivity_onCreate")
target_link_libraries(main PRIVATE raylib log android EGL GLESv2 OpenSLES atomic c dl m)
