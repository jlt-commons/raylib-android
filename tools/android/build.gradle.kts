// The root project builds nothing; :app is the one module. Pinned rather than
// floating, because an AGP upgrade changes the NDK contract and the CMake
// arguments it passes, and this project's whole native story runs through
// those. AGP 8.7 wants Gradle 8.9+ and a JDK 17 toolchain.
plugins {
  id("com.android.application") version "8.7.3" apply false
}
