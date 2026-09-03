plugins {
  id("com.android.application")
}

// One knob, read from gradle.properties (or -Praylib.apiLevel=NN), shared with
// tools/android/pack.sh so the Chez cross-build and the APK agree.
val apiLevel = (project.findProperty("raylib.apiLevel") as String? ?: "26").toInt()

// The pinned raylib tree. tools/android/build.sh exports RAYLIB_SOURCE;
// -Praylib.source overrides it for a one-off.
val raylibSource: String =
  (project.findProperty("raylib.source") as String?)
    ?: System.getenv("RAYLIB_SOURCE")
    ?: throw GradleException(
      "RAYLIB_SOURCE is unset. Run `sh tools/android/deps.sh`, then build " +
        "through `sh tools/android/build.sh`, which exports it.")

// The installed NDK, which tools/android/build.sh discovers and passes so that
// the Chez cross-compiler and this build use one toolchain. Left unset, AGP
// picks its own default and the two can disagree.
val ndk = project.findProperty("raylib.ndkVersion") as String?

android {
  namespace = "io.github.jltcommons.raylib"
  compileSdk = 35
  if (ndk != null) {
    ndkVersion = ndk
  }

  defaultConfig {
    applicationId = "io.github.jltcommons.raylib"
    minSdk = apiLevel
    targetSdk = 35
    versionCode = 1
    versionName = "0.1.0"

    // arm64 only, and deliberately: Chez is cross-compiled once, for
    // tarm64le. A second ABI would mean a second target pack and a second
    // fifteen-minute Chez build for a device nobody here has.
    ndk { abiFilters += "arm64-v8a" }

    externalNativeBuild {
      cmake {
        // gnu17, not c17: Bionic's unistd.h hides gettid() under
        // __STRICT_ANSI__, which -std=c17 defines, and main.c logs the owner
        // thread id. gnu17 is also the NDK's own default.
        cFlags += listOf("-std=gnu17", "-Wall", "-Wextra")
        arguments += "-DRAYLIB_SOURCE=$raylibSource"
      }
    }
  }

  externalNativeBuild {
    cmake {
      path = file("src/main/cpp/CMakeLists.txt")
      version = "3.22.1"
    }
  }

  buildTypes {
    // NDEBUG is what main.c switches on: CMake defines it for a release
    // variant (RelWithDebInfo) and not for a debug one, which is how the
    // release image comes to demand raylib_main and refuse raylib_main_debug.
    getByName("release") {
      isMinifyEnabled = false      // nothing to shrink: hasCode is false
    }
  }

  // libjoltraylib.so is staged per build type -- src/debug/jniLibs for a debug
  // build, src/release/jniLibs for a release one -- which are AGP's default
  // locations, so no source set needs declaring. Keeping them apart is what
  // makes it impossible for a release APK to pick up a debug library that
  // happens to be lying around, which one shared staging directory allows.
  packaging {
    jniLibs {
      useLegacyPackaging = false
    }
  }
}
