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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
