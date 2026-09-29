import com.android.build.api.variant.HasHostTestsBuilder
import com.android.build.api.variant.HostTestBuilder
import java.util.Properties
import javax.inject.Inject

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
}

// CloudKit public read 用 API token は local.properties (git管理外) / 環境変数から注入する。
// 未設定でもアプリは起動する: 初回は db/master.sql から生成した seed DB を投入するので
// (generate<Variant>SeedDb タスク + SeedImporter)、コントリビューターは token 無しで完動できる。
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

// Room に確定スキーマを JSON で吐かせる (トップレベルでないと効かない)。
// 共有コア (imas-core) が持つマスタ DDL とここが食い違うと、片方だけスキーマを
// 変えた事故になる (idol_voice_actors が iOS にだけ在って Android の CV 名検索が
// 常に 0 件だった、が実例)。吐いた JSON はコア側のテストで突き合わせる。
ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

android {
    namespace = "com.fugaif.imaslivedb"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        // 公開時の Play パッケージ ID = 所有ドメイン fugaapp.site の逆DNSで一本化。
        // namespace (Kotlin パッケージ/R/BuildConfig) は com.fugaif のまま (内部のみ・非公開)。
        applicationId = "site.fugaapp.imaslivedb"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 5
        versionName = "2.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "CLOUDKIT_API_TOKEN", "\"$cloudKitApiToken\"")

        // 共有コア (libimas_core.so) は arm64-v8a と x86_64 (エミュ) の 2 つだけビルドする
        // (imas-core/build.sh)。32bit 端末にも配ると、初回起動でコアを読み込めずに落ちる
        // (UnsatisfiedLinkError は Error なので catch (e: Exception) では捕まらない)。
        // 配布対象を 64bit に絞る。JNA などが同梱する 32bit・mips の .so も入らなくなる。
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
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

    sourceSets {
        // Room の確定スキーマ (app/schemas) を JVM ユニットテストから読める assets に載せる。
        // MigrationTestHelper は assets の `<DB クラス名>/<版>.json` から旧版の DB を組み立てる。
        // test ソースセットの assets は AGP がユニットテストに渡さない (Robolectric が見るのは
        // debug の merged assets だけ) ので、debug に足す。release の APK には入らない。
        getByName("debug") {
            assets.srcDirs("$projectDir/schemas")
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    testOptions {
        // Robolectric (SongDao 等の Room テスト) がアプリのマニフェスト/リソースを見られるように。
        unitTests.isIncludeAndroidResources = true
        unitTests.all {
            // imas-core (Rust) を JVM ユニットテストから叩くため、ホスト向け dylib の場所を JNA に教える。
            // imas-core/build.sh の host ビルドが生成する (未生成ならテスト前に実行)。
            it.systemProperty(
                "jna.library.path",
                rootProject.file("../imas-core/target/release").absolutePath,
            )
        }
    }
}

// db/master.sql (monorepo の唯一の真実の源・text・diff可) から Android 同梱用の seed sqlite を
// ビルド時に生成する (iOS の tools/build_db.sh と同じ思想)。これで初回起動時に SeedImporter が
// 実データを投入でき、コントリビューターは CloudKit token 無しで完動する。
// 出力は build の下に置き、variant の assets に足す。src/main/assets に書いていた頃は、
// そこに残った古い -shm / -wal まで APK に入っていた。
// dump が無い環境 (db/ を含まない clone 等) では seed を作らず、CloudKit 同期にフォールバックする。
abstract class GenerateSeedDb : DefaultTask() {
    @get:InputFile
    @get:Optional
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val dump: RegularFileProperty

    /** 中身は seed 1 つだけ。毎回空にしてから作る (前の生成の残り物を assets に載せない)。 */
    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @get:Inject
    abstract val execOperations: ExecOperations

    @TaskAction
    fun generate() {
        val dir = outputDir.get().asFile
        dir.deleteRecursively()
        dir.mkdirs()
        val source = dump.orNull?.asFile ?: return
        val seed = File(dir, "master_seed.sqlite")
        execOperations.exec { commandLine("sqlite3", seed.absolutePath, ".read ${source.absolutePath}") }
    }
}

// JVM の単体テストは debug でだけ回す。単体テストが見るコードは debug も release も同じで
// (R8 は単体テストに掛からない)、移行テストが読むスキーマ JSON は debug の assets にしか
// 置かない (release の APK に入れないため)。release でも回すと移行テストが JSON を見つけられない。
androidComponents {
    beforeVariants(selector().withBuildType("release")) { variant ->
        (variant as HasHostTestsBuilder).hostTests[HostTestBuilder.UNIT_TEST_TYPE]?.enable = false
    }
    // seed (上の GenerateSeedDb) は variant ごとに作り、その variant の assets に足す。
    onVariants { variant ->
        val seed = tasks.register<GenerateSeedDb>("generate${variant.name.replaceFirstChar { it.uppercase() }}SeedDb") {
            description = "db/master.sql から ${variant.name} に同梱する seed sqlite を生成"
            rootProject.file("../db/master.sql").takeIf { it.exists() }?.let { dump.set(it) }
        }
        variant.sources.assets?.addGeneratedSourceDirectory(seed, GenerateSeedDb::outputDir)
    }
}

// app/schemas は KSP (Room) が書き出し、debug の assets がそれを読む (移行テスト用)。
// Gradle はこの受け渡しを知らないので、版を上げた回のビルドでも新しい JSON が assets に
// 載るよう、assets の統合を KSP の後にする。
tasks.matching { it.name == "mergeDebugAssets" }.configureEach { dependsOn("kspDebugKotlin") }

dependencies {
    // imas-core (Rust) の UniFFI バインディング用 JNA。
    // @aar は実機/エミュ (jniLibs の libimas_core.so をロード)、
    // 素の jar は JVM ユニットテスト (jna.library.path のホスト dylib をロード)。
    implementation(variantOf(libs.jna) { artifactType("aar") })
    testImplementation(libs.jna)

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

    // ホーム画面ウィジェット (Glance)。
    // バージョンをカタログ (libs.versions.toml) ではなくここに直書きしているのは、
    // ウィジェット以外がこの依存を参照しないため。1.1.1 を選んでいるのは、要求する
    // compose-runtime の下限が低く (1.1.1)、アプリ本体が使う Compose BOM の版が
    // そのまま採用されるから (新しい Glance を入れると runtime だけ BOM から外れて
    // 版が混ざる)。WorkManager は要求しないので、更新の予約は AlarmManager のまま
    // (理由は WidgetUpdateScheduler の KDoc)。
    implementation("androidx.glance:glance-appwidget:1.1.1")

    // Coil
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    // Media3
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui)
    implementation(libs.androidx.media3.session)

    // Auth (Google Sign-In / Credential Manager)
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services.auth)
    implementation(libs.googleid)
    implementation(libs.androidx.security.crypto)

    // Debug
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)

    // Test
    testImplementation(libs.junit)
    // Room DAO (SongDao 等) を Android 実機/エミュ無しで JVM ユニットテストから叩くため。
    testImplementation(libs.robolectric)
    // Room の移行を旧版のスキーマ JSON から組み立てて検証する (MigrationTestHelper)。
    testImplementation(libs.androidx.room.testing)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
}
