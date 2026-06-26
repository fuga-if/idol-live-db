# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in /path/to/android-sdk/tools/proguard/proguard-android.txt

# Keep Room entities
-keep class com.fugaif.imaslivedb.models.** { *; }
-keep class com.fugaif.imaslivedb.database.** { *; }

# Keep data classes used for Compose
-keep class com.fugaif.imaslivedb.** { *; }

# Coil
-dontwarn coil.**

# Media3 / ExoPlayer
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
