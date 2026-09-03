// The Gradle build lives under tools/android so the repository root stays a
// Clojure project: there is no Java or Kotlin source anywhere in this tree, and
// Gradle is here only to compile main.c, run raylib's own CMake and zip an APK.
pluginManagement {
  repositories {
    google()
    mavenCentral()
    gradlePluginPortal()
  }
}

dependencyResolutionManagement {
  repositories {
    google()
    mavenCentral()
  }
}

rootProject.name = "raylib-android"
include(":app")
