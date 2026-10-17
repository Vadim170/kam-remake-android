package org.kamremake.android;

/** Bridge to the native KaM Remake engine (libkamhost.so -> libkamcore.so). All calls on the GL thread. */
final class KaMNative {
    static {
        try {
            // gl4es settings (read when the engine loads libGL.so)
            android.system.Os.setenv("LIBGL_LOGSHADERERROR", "1", true);
        } catch (Exception ignored) {
        }
        System.loadLibrary("kamhost");
    }

    static volatile KaMActivity activity;

    static native boolean init(String dataDir, int width, int height);
    static native void frame();
    static native void resize(int width, int height);
    static native void pause();
    static native void resume();
    static native void shutdown();
    static native void touch(int action, int count, float x0, float y0, float x1, float y1);
    static native void mouse(int action, int button, int x, int y);
    static native void wheel(int steps, int x, int y);
    static native void key(int action, int vk, int shift);
    static native void charInput(int ch);
    static native void back();
    static native boolean textInputActive();
    static native void videoFinished();
    static native boolean inGame();
    static native int textInputBottom();
    static native boolean textFieldTapped();
    static native void selfTest(String mode);

    // Called from native code (GL thread)
    static void onShowMessage(String title, String text) {
        KaMActivity a = activity;
        if (a != null) a.showMessage(title, text);
    }

    static void onClipboardSet(String text) {
        KaMActivity a = activity;
        if (a != null) a.setClipboard(text);
    }

    static String onClipboardGet() {
        KaMActivity a = activity;
        return a != null ? a.getClipboard() : "";
    }

    static void onOpenURL(String url) {
        KaMActivity a = activity;
        if (a != null) a.openUrl(url);
    }

    static void onQuit() {
        KaMActivity a = activity;
        if (a != null) a.quit();
    }

    static void onPlayVideo(String path, int volume, boolean stretch) {
        KaMActivity a = activity;
        if (a != null) a.playVideo(path, volume, stretch);
    }

    static void onStopVideo() {
        KaMActivity a = activity;
        if (a != null) a.stopVideo();
    }

    private KaMNative() {}
}
