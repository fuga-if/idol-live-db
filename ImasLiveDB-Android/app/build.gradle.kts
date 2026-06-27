import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
}

// CloudKit public read 用 API token は local.properties (git管理外) / 環境変数から注入する。
// 未設定でもアプリは起動する: 初回は db/master.sql から生成した seed DB を投入するので
// (generateSeedDb タスク + SeedImporter)、コントリビューターは token 無しで完動できる。
// token は「リリース版で CloudKit から最新差分を取る」ためだけに使う (未設定なら同期スキップ)。
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val cloudKitApiToken: String =
    localProps.getProperty("cloudkit.api.token") ?: System.getenv("CLOUDKIT_API_TOKEN") ?: ""

// リリース署名情報 (keystore/パスワードは git に入れず local.properties から)。
val releaseStoreFile = localProps.getProperty("RELEASE_STORE_FILE")
val hasReleaseSigning = releaseStoreFile != null && rootProject.file("app/$releaseStoreFile").exists()

android {
    namespace = "com.fugaif.imaslivedb"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        // 公開時の Play パッケージ ID = 所有ドメイン fugaapp.site の逆DNSで一本化。
        // namespace (Kotlin パッケージ/R/BuildConfig) は com.fugaif のまま (内部のみ・非公開)。
        applicationId = "site.fugaapp.imaslivedb"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 2
        versionName = "1.8.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "CLOUDKIT_API_TOKEN", "\"$cloudKitApiToken\"")
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file("app/$releaseStoreFile")
                storePassword = localProps.getProperty("RELEASE_STORE_PASSWORD")
                keyAlias = localProps.getProperty("RELEASE_KEY_ALIAS")
                keyPassword = localProps.getProperty("RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
        }
        debug {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // Assets source set for master.sqlite
    sourceSets {
        getByName("main") {
            assets.srcDirs("src/main/assets")
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

// db/master.sql (monorepo の唯一の真実の源・text・diff可) から Android 同梱用の seed sqlite を
// ビルド時に生成する。binary seed は gitignore で各自/CI が生成 (iOS の tools/build_db.sh と同じ思想)。
// これで初回起動時に SeedImporter が実データを投入でき、コントリビューターは CloudKit token 無しで完動する。
// dump が無い環境 (db/ を含まない clone 等) では skip し、従来通り CloudKit 同期にフォールバックする。
val generateSeedDb by tasks.registering(Exec::class) {
    description = "db/master.sql から Android 同梱 seed sqlite を生成"
    val dump = rootProject.file("../db/master.sql")
    val seed = file("src/main/assets/master_seed.sqlite")
    onlyIf { dump.exists() }
    inputs.file(dump).optional()
    outputs.file(seed)
    doFirst {
        seed.parentFile.mkdirs()
        seed.delete()
    }
    commandLine("sqlite3", seed.absolutePath, ".read ${dump.absolutePath}")
}

tasks.named("preBuild") { dependsOn(generateSeedDb) }

dependencies {
    // AndroidX Core
    implementation(libs.androidx.core.ktx)

    // Lifecycle
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)

    // Activity
    implementation(libs.androidx.activity.compose)

    // Compose BOM
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)

    // Navigation
    implementation(libs.androidx.navigation.compose)

    // Room
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    // Coil
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    // Media3
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui)
    implementation(libs.androidx.media3.session)

    // Debug
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)

    // Test
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
}
