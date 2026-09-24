import org.gradle.authentication.http.BasicAuthentication

allprojects {
    repositories {
        google()
        mavenCentral()
        // The Mapbox Maps SDK for Android (pulled in by mapbox_maps_flutter) is
        // served from Mapbox's own Maven repository, which needs a *secret*
        // downloads token (sk.… with the DOWNLOADS:READ scope). Do not commit
        // it — set MAPBOX_DOWNLOADS_TOKEN in ~/.gradle/gradle.properties (or as
        // an environment variable) and it is picked up here.
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication {
                create<BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password = (project.findProperty("MAPBOX_DOWNLOADS_TOKEN") as String?)
                    ?: System.getenv("MAPBOX_DOWNLOADS_TOKEN")
                    ?: ""
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// mapbox_maps_flutter 2.31.0 skips applying the Kotlin Gradle Plugin when it
// detects AGP 9+ (its build.gradle assumes AGP's built-in Kotlin provides the
// `kotlin { }` extension), but that built-in support doesn't cover this library
// subproject — so its own `kotlin { compilerOptions { … } }` block fails with
// "Could not find method kotlin()". Apply the Kotlin Android plugin for it, the
// same one the app module uses.
subprojects {
    if (name == "mapbox_maps_flutter") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
