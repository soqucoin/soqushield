# Flutter-specific ProGuard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_secure_storage — keeps tink crypto + AndroidX security
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
-keep class androidx.security.crypto.** { *; }

# local_auth
-keep class io.flutter.plugins.localauth.** { *; }

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Hive
-keep class com.cossacklabs.** { *; }

# Suppress missing Play Core classes (Flutter deferred components — not used)
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Suppress other common warnings
-dontwarn javax.annotation.**
-dontwarn kotlin.reflect.jvm.internal.**
