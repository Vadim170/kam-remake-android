package org.kamremake.android;

import android.net.Uri;
import android.view.View;
import android.widget.FrameLayout;

import org.videolan.libvlc.LibVLC;
import org.videolan.libvlc.Media;
import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.util.VLCVideoLayout;

import java.io.File;
import java.util.ArrayList;

/** Fullscreen video player for game intros and campaign videos. Tap skips the video. */
final class VideoOverlay {
    private final KaMActivity activity;
    private final FrameLayout root;
    private LibVLC vlc;
    private MediaPlayer player;
    private VLCVideoLayout layout;
    private Runnable onDone;

    VideoOverlay(KaMActivity activity, FrameLayout root) {
        this.activity = activity;
        this.root = root;
    }

    boolean isPlaying() {
        return layout != null;
    }

    void play(String path, int volume, boolean stretch, Runnable onDone) {
        stop(false);
        this.onDone = onDone;
        if (!new File(path).exists()) {
            finish();
            return;
        }
        if (vlc == null) {
            ArrayList<String> opts = new ArrayList<>();
            opts.add("--no-osd");
            vlc = new LibVLC(activity, opts);
        }
        layout = new VLCVideoLayout(activity);
        layout.setBackgroundColor(0xFF000000);
        layout.setOnClickListener(v -> finish());
        root.addView(layout, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        player = new MediaPlayer(vlc);
        player.attachViews(layout, null, false, false);
        player.setVideoScale(stretch ? MediaPlayer.ScaleType.SURFACE_FILL : MediaPlayer.ScaleType.SURFACE_BEST_FIT);
        Media media = new Media(vlc, Uri.fromFile(new File(path)));
        player.setMedia(media);
        media.release();
        player.setEventListener(e -> {
            if (e.type == MediaPlayer.Event.EndReached || e.type == MediaPlayer.Event.EncounteredError)
                activity.runOnUiThread(this::finish);
        });
        player.play();
        player.setVolume(Math.max(0, Math.min(100, volume)));
    }

    /** Ends playback and reports completion to the game */
    void finish() {
        stop(true);
    }

    private void stop(boolean notify) {
        if (player != null) {
            player.setEventListener(null);
            player.stop();
            player.detachViews();
            player.release();
            player = null;
        }
        if (layout != null) {
            root.removeView(layout);
            layout = null;
        }
        Runnable r = onDone;
        onDone = null;
        if (notify && r != null) r.run();
    }

    void release() {
        stop(false);
        if (vlc != null) {
            vlc.release();
            vlc = null;
        }
    }
}
