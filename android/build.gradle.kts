allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// flutter_pcm_sound 같은 일부 플러그인은 compileSdk 가 낮게 고정돼 있는데,
// 최신 androidx 의존성이 더 높은 값을 요구해서 빌드가 막힌다.
// (file_picker 는 34 로 고정인데 그것이 끌고 오는 flutter_plugin_android_lifecycle
//  2.0.35 가 **36 이상**을 요구한다 — 그대로 두면 빌드가 아예 안 된다.)
// 하위 모듈 전부를 36 / minSdk 23 으로 맞춘다.
// `compileSdk` 는 **무엇으로 컴파일하는가**일 뿐이다 — 폰에서 어떻게 도는지는
// app 모듈의 `targetSdk` 가 정하고, 그건 안 건드린다.
// ※ 아래 evaluationDependsOn(":app") 보다 **먼저** 등록해야 한다.
//   그 뒤에 두면 이미 평가가 끝나서 "already evaluated" 오류가 난다.
subprojects {
    afterEvaluate {
        val ext = extensions.findByName("android")
        if (ext is com.android.build.gradle.BaseExtension) {
            val cur = ext.compileSdkVersion
            if (cur == null || cur < "android-36") {
                ext.compileSdkVersion(36)
            }
            if ((ext.defaultConfig.minSdk ?: 0) < 23) {
                ext.defaultConfig.minSdk = 23
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
