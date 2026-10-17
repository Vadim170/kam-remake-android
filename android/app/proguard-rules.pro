# Called from native code (kamhost.c) by name: keep JNI natives and static callbacks
-keep class org.kamremake.android.KaMNative { *; }
# libVLC uses JNI and reflection internally
-keep class org.videolan.libvlc.** { *; }
-keep class org.videolan.medialibrary.** { *; }
-dontwarn org.videolan.**
