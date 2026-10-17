package org.kamremake.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

import java.io.File;

public class KaMActivity extends Activity {
    private static final String PREFS = "kam";
    private static final String PREF_UI_SCALE = "ui_scale";

    private KaMView view;
    private FrameLayout root;
    private TextView overlay;
    private String dataDir;
    private volatile boolean engineRunning;
    private VideoOverlay video;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        // Use the whole screen including the camera cutout area
        WindowManager.LayoutParams lp = getWindow().getAttributes();
        lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        getWindow().setAttributes(lp);
        getWindow().setDecorFitsSystemWindows(false);
        KaMNative.activity = this;

        root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        setContentView(root);
        hideSystemBars();

        File dir = getExternalFilesDir(null);
        dataDir = dir.getAbsolutePath() + "/";

        // APK with bundled game data: extract it on first launch
        if (!DataInstaller.isInstalled(dir) && DataInstaller.hasBundledData(getAssets())) {
            installBundledData(dir);
            return;
        }

        if (!new File(dir, "data/defines/houses.dat").exists()) {
            showMissingData(dir);
            return;
        }

        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        // Optional launch parameter (adb shell am start ... --ef ui_scale 1.5), same as the settings slider
        float extraScale = getIntent().getFloatExtra(PREF_UI_SCALE, -1);
        if (extraScale >= 0.5f && extraScale <= 2.0f) prefs.edit().putFloat(PREF_UI_SCALE, extraScale).apply();
        float uiScale = prefs.getFloat(PREF_UI_SCALE, 1.0f);
        view = new KaMView(this, dataDir, uiScale);
        // Track the soft keyboard height to keep text fields visible above it
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            view.setImeHeight(insets.getInsets(WindowInsets.Type.ime()).bottom);
            return insets;
        });
        root.addView(view, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        overlay = new TextView(this);
        overlay.setText("Knights and Merchants\nloading…");
        overlay.setTextColor(Color.rgb(230, 210, 160));
        overlay.setTextSize(22);
        overlay.setGravity(Gravity.CENTER);
        overlay.setBackgroundColor(Color.BLACK);
        root.addView(overlay, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        view.requestFocus();
    }

    private void installBundledData(File dir) {
        TextView t = new TextView(this);
        t.setTextColor(Color.rgb(230, 210, 160));
        t.setTextSize(20);
        t.setGravity(Gravity.CENTER);
        t.setText("Knights and Merchants\nInstalling game data…");
        root.addView(t, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        new Thread(() -> {
            try {
                DataInstaller.install(getAssets(), dir, (done, total) -> runOnUiThread(() ->
                        t.setText(String.format("Knights and Merchants\nInstalling game data… %d%%", total > 0 ? done * 100 / total : 0))));
                runOnUiThread(this::recreate);
            } catch (Exception e) {
                runOnUiThread(() -> t.setText("Failed to install game data:\n" + e.getMessage()));
            }
        }, "KaMDataInstall").start();
    }

    private void showMissingData(File dir) {
        TextView t = new TextView(this);
        t.setTextColor(Color.WHITE);
        t.setTextSize(16);
        t.setPadding(48, 48, 48, 48);
        t.setText("Game data not found.\n\nCopy the KaM Remake game folder (data, Campaigns, Maps, MapsMP, Music, Sounds, Tutorials) to:\n\n"
                + dir.getAbsolutePath() + "\n\nand start the app again.");
        root.addView(t);
    }

    private void hideSystemBars() {
        WindowInsetsController c = getWindow().getInsetsController();
        if (c != null) {
            c.hide(WindowInsets.Type.systemBars());
            c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemBars();
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (view != null) {
            if (engineRunning) view.queueEvent(KaMNative::pause);
            view.onPause();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (view != null) {
            view.onResume();
            if (engineRunning) view.queueEvent(KaMNative::resume);
        }
        hideSystemBars();
    }

    @Override
    protected void onDestroy() {
        if (view != null) view.exit();
        if (video != null) video.release();
        if (KaMNative.activity == this) KaMNative.activity = null;
        super.onDestroy();
    }

    // ---------- Called by the view / native code ----------

    void onEngineStarted() {
        engineRunning = true;
        // Content smoke test: adb shell am start -n org.kamremake.android/.KaMActivity --es kam_selftest campaigns
        String test = getIntent().getStringExtra("kam_selftest");
        if (test != null && view != null) view.queueEvent(() -> KaMNative.selfTest(test));
        runOnUiThread(() -> {
            if (overlay != null) {
                root.removeView(overlay);
                overlay = null;
            }
        });
    }

    void onEngineFailed() {
        runOnUiThread(() -> {
            if (overlay != null) overlay.setText("Failed to start the game.\nSee Logs folder in " + dataDir);
        });
    }

    void showMessage(String title, String text) {
        runOnUiThread(() -> new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(text)
                .setPositiveButton(android.R.string.ok, null)
                .show());
    }

    void setClipboard(String text) {
        runOnUiThread(() -> {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            cm.setPrimaryClip(ClipData.newPlainText("KaM", text));
        });
    }

    String getClipboard() {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        ClipData clip = cm.getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0) return "";
        CharSequence s = clip.getItemAt(0).coerceToText(this);
        return s != null ? s.toString() : "";
    }

    void openUrl(String url) {
        runOnUiThread(() -> {
            try {
                Intent i;
                if (url.startsWith("/")) {
                    // Local file (e.g. map PDF): share through FileProvider
                    File f = new File(url);
                    Uri uri = androidx.core.content.FileProvider.getUriForFile(this, getPackageName() + ".files", f);
                    String ext = android.webkit.MimeTypeMap.getFileExtensionFromUrl(f.getName()).toLowerCase();
                    String mime = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
                    i = new Intent(Intent.ACTION_VIEW);
                    i.setDataAndType(uri, mime != null ? mime : "*/*");
                    i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                } else {
                    i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                }
                startActivity(i);
            } catch (Exception e) {
                android.widget.Toast.makeText(this, "Can't open " + url, android.widget.Toast.LENGTH_SHORT).show();
            }
        });
    }

    void quit() {
        engineRunning = false;
        runOnUiThread(this::finishAndRemoveTask);
    }

    void playVideo(String path, int volume, boolean stretch) {
        runOnUiThread(() -> {
            if (video == null) video = new VideoOverlay(this, root);
            video.play(path, volume, stretch, () -> {
                if (view != null) view.queueEvent(KaMNative::videoFinished);
                if (view != null) view.requestFocus();
            });
        });
    }

    void stopVideo() {
        runOnUiThread(() -> {
            if (video != null && video.isPlaying()) video.finish();
        });
    }

    @Override
    public void onBackPressed() {
        if (video != null && video.isPlaying()) {
            video.finish();
            return;
        }
        if (view != null) view.queueEvent(KaMNative::back);
    }

    void setSoftKeyboardVisible(boolean visible) {
        InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
        if (visible) {
            view.requestFocus();
            imm.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT);
        } else {
            imm.hideSoftInputFromWindow(view.getWindowToken(), 0);
        }
    }

    /** Android-only settings (three finger tap): interface scale */
    void showPortSettings() {
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        float current = prefs.getFloat(PREF_UI_SCALE, 1.0f);

        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(48, 24, 48, 24);
        TextView label = new TextView(this);
        SeekBar bar = new SeekBar(this);
        // 0.5 .. 2.0 in 0.05 steps. Above 1.0 only the in-game interface grows, menus keep their design size
        bar.setMax(30);
        bar.setProgress(Math.round((current - 0.5f) / 0.05f));
        label.setText(String.format("Interface scale: %.2f", current));
        bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar s, int p, boolean user) {
                label.setText(String.format("Interface scale: %.2f", 0.5f + p * 0.05f));
            }

            @Override
            public void onStartTrackingTouch(SeekBar s) {}

            @Override
            public void onStopTrackingTouch(SeekBar s) {}
        });
        box.addView(label);
        box.addView(bar);

        new AlertDialog.Builder(this)
                .setTitle("KaM Remake for Android")
                .setView(box)
                .setPositiveButton(android.R.string.ok, (d, w) -> {
                    float scale = 0.5f + bar.getProgress() * 0.05f;
                    prefs.edit().putFloat(PREF_UI_SCALE, scale).apply();
                    if (view != null) view.setUiScale(scale);
                })
                .setNegativeButton(android.R.string.cancel, null)
                .show();
    }
}
