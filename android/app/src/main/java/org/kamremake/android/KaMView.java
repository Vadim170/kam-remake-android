package org.kamremake.android;

import android.content.Context;
import android.opengl.GLSurfaceView;
import android.os.SystemClock;
import android.text.InputType;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * Fullscreen GL surface the game renders into.
 * The surface buffer has a fixed "virtual" size (the game's screen resolution) that the hardware
 * scaler stretches to the display, so the original UI keeps its proportions and stays readable.
 */
final class KaMView extends GLSurfaceView implements GLSurfaceView.Renderer {
    // Minimal game resolution the original UI is designed for
    static final int BASE_WIDTH = 1024;
    static final int BASE_HEIGHT = 720;
    // Smallest game resolution while playing (sidebar must still fit)
    static final int MIN_GAME_WIDTH = 640;
    static final int MIN_GAME_HEIGHT = 400; // Sidebar scrolls vertically when it does not fit

    private final KaMActivity activity;
    private final String dataDir;
    private float uiScale;

    private volatile int virtW, virtH;
    private volatile boolean inGame;
    private volatile float touchScaleX = 1, touchScaleY = 1;
    private boolean engineStarted;
    private boolean engineFailed;
    private boolean textInputShown;
    private volatile int textInputBottom = -1;
    private int imeHeight;
    private long lastTextInputCheck;

    KaMView(KaMActivity activity, String dataDir, float uiScale) {
        super(activity);
        this.activity = activity;
        this.dataDir = dataDir;
        this.uiScale = uiScale;
        setEGLContextClientVersion(2);
        setEGLConfigChooser(8, 8, 8, 8, 16, 8);
        setPreserveEGLContextOnPause(true);
        setRenderer(this);
        setRenderMode(RENDERMODE_CONTINUOUSLY);
        setFocusable(true);
        setFocusableInTouchMode(true);
    }

    /**
     * Game resolution for the given display size. The smaller UI dimension fits the base UI size, scaled by user preference.
     * Menus are designed for 1024x720 and never get less; in game (map + sidebar) the UI can be made up to 2x larger.
     */
    private void computeVirtualSize(int w, int h) {
        float scale = Math.min((float) h / BASE_HEIGHT, (float) w / BASE_WIDTH) * uiScale;
        scale = Math.max(scale, 0.25f);
        int minW = inGame ? MIN_GAME_WIDTH : BASE_WIDTH;
        int minH = inGame ? MIN_GAME_HEIGHT : BASE_HEIGHT;
        int vw = Math.max(minW, Math.round(w / scale));
        int vh = Math.max(minH, Math.round(h / scale));
        // Keep display aspect ratio
        float aspect = (float) w / h;
        if ((float) vw / vh < aspect) vw = Math.round(vh * aspect);
        else vh = Math.round(vw / aspect);
        virtW = vw & ~1;
        virtH = vh & ~1;
        touchScaleX = (float) virtW / w;
        touchScaleY = (float) virtH / h;
    }

    private void applyVirtualSize() {
        if (getWidth() <= 0) return;
        computeVirtualSize(getWidth(), getHeight());
        getHolder().setFixedSize(virtW, virtH);
    }

    void setUiScale(float scale) {
        uiScale = scale;
        applyVirtualSize();
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        if (w <= 0 || h <= 0) return;
        computeVirtualSize(w, h);
        getHolder().setFixedSize(virtW, virtH);
    }

    // ---------- Renderer (GL thread) ----------

    @Override
    public void onSurfaceCreated(GL10 gl, EGLConfig config) {
    }

    @Override
    public void onSurfaceChanged(GL10 gl, int width, int height) {
        if (engineFailed) return;
        if (!engineStarted) {
            engineStarted = true;
            if (!KaMNative.init(dataDir, width, height)) {
                engineFailed = true;
                activity.onEngineFailed();
                return;
            }
            activity.onEngineStarted();
        } else {
            KaMNative.resize(width, height);
        }
    }

    @Override
    public void onDrawFrame(GL10 gl) {
        if (!engineStarted || engineFailed) return;
        KaMNative.frame();

        boolean ig = KaMNative.inGame();
        if (ig != inGame) {
            inGame = ig;
            activity.runOnUiThread(this::applyVirtualSize);
        }

        long now = SystemClock.uptimeMillis();
        if (now - lastTextInputCheck > 200) {
            lastTextInputCheck = now;
            boolean active = KaMNative.textInputActive();
            // Show the keyboard only when the user tapped a text field, not when the game focuses
            // a field by itself (e.g. lobby chat). Hide it as soon as no field has focus
            if (KaMNative.textFieldTapped() && active) {
                textInputShown = true;
                activity.runOnUiThread(() -> activity.setSoftKeyboardVisible(true));
            } else if (!active && textInputShown) {
                textInputShown = false;
                activity.runOnUiThread(() -> activity.setSoftKeyboardVisible(false));
            }
            final int bottom = active ? KaMNative.textInputBottom() : -1;
            if (bottom != textInputBottom) {
                textInputBottom = bottom;
                activity.runOnUiThread(this::updateKeyboardShift);
            }
        }
    }

    // ---------- Soft keyboard: keep the focused text field visible ----------

    void setImeHeight(int h) {
        imeHeight = h;
        updateKeyboardShift();
    }

    /** Moves the game picture up while the keyboard covers the focused text field (UI thread) */
    private void updateKeyboardShift() {
        float shift = 0;
        if (imeHeight > 0 && textInputBottom >= 0 && touchScaleY > 0) {
            float fieldBottomPx = textInputBottom / touchScaleY + 16 * getResources().getDisplayMetrics().density;
            float visible = getHeight() - imeHeight;
            shift = Math.max(0, fieldBottomPx - visible);
        }
        setTranslationY(-shift);
    }

    // ---------- Input (UI thread -> GL thread) ----------

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        if (e.isFromSource(InputDevice.SOURCE_MOUSE)) return handleMouse(e);

        final int action = e.getActionMasked();
        final int count = e.getPointerCount();
        final float x0 = e.getX(0) * touchScaleX, y0 = e.getY(0) * touchScaleY;
        final float x1 = count > 1 ? e.getX(1) * touchScaleX : x0;
        final float y1 = count > 1 ? e.getY(1) * touchScaleY : y0;
        int a;
        switch (action) {
            case MotionEvent.ACTION_DOWN: a = 0; break;
            case MotionEvent.ACTION_MOVE: a = 1; break;
            case MotionEvent.ACTION_UP: a = 2; break;
            case MotionEvent.ACTION_CANCEL: a = 3; break;
            case MotionEvent.ACTION_POINTER_DOWN:
                if (count == 3) {
                    activity.runOnUiThread(activity::showPortSettings);
                    return true;
                }
                a = 5;
                break;
            case MotionEvent.ACTION_POINTER_UP: a = 6; break;
            default: return true;
        }
        final int fa = a;
        queueEvent(() -> KaMNative.touch(fa, count, x0, y0, x1, y1));
        return true;
    }

    private int lastMouseButtons;

    private boolean handleMouse(MotionEvent e) {
        final int x = Math.round(e.getX() * touchScaleX), y = Math.round(e.getY() * touchScaleY);
        int buttons = e.getButtonState();
        int changed = buttons ^ lastMouseButtons;
        int[][] map = {{MotionEvent.BUTTON_PRIMARY, 0}, {MotionEvent.BUTTON_SECONDARY, 1}, {MotionEvent.BUTTON_TERTIARY, 2}};
        for (int[] m : map) {
            if ((changed & m[0]) != 0) {
                final int act = (buttons & m[0]) != 0 ? 0 : 2;
                final int btn = m[1];
                queueEvent(() -> KaMNative.mouse(act, btn, x, y));
            }
        }
        lastMouseButtons = buttons;
        if (changed == 0) queueEvent(() -> KaMNative.mouse(1, 0, x, y));
        return true;
    }

    @Override
    public boolean onGenericMotionEvent(MotionEvent e) {
        if (e.isFromSource(InputDevice.SOURCE_CLASS_POINTER)) {
            final int x = Math.round(e.getX() * touchScaleX), y = Math.round(e.getY() * touchScaleY);
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_HOVER_MOVE:
                    queueEvent(() -> KaMNative.mouse(1, 0, x, y));
                    return true;
                case MotionEvent.ACTION_SCROLL:
                    final int steps = Math.round(e.getAxisValue(MotionEvent.AXIS_VSCROLL));
                    if (steps != 0) queueEvent(() -> KaMNative.wheel(steps, x, y));
                    return true;
                case MotionEvent.ACTION_BUTTON_PRESS:
                case MotionEvent.ACTION_BUTTON_RELEASE:
                    return handleMouse(e);
            }
        }
        return super.onGenericMotionEvent(e);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent e) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            activity.onBackPressed();
            return true;
        }
        int vk = KeyMap.toVK(keyCode);
        final int shift = KeyMap.shiftFlags(e);
        if (vk != 0) {
            final int fvk = vk;
            queueEvent(() -> KaMNative.key(0, fvk, shift));
        }
        int ch = e.getUnicodeChar();
        if (ch >= 32) {
            final int fch = ch;
            queueEvent(() -> KaMNative.charInput(fch));
        } else if (keyCode == KeyEvent.KEYCODE_DEL) {
            queueEvent(() -> KaMNative.charInput(8));
        } else if (keyCode == KeyEvent.KEYCODE_ENTER) {
            queueEvent(() -> KaMNative.charInput(13));
        }
        return vk != 0 || ch != 0 || super.onKeyDown(keyCode, e);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent e) {
        if (keyCode == KeyEvent.KEYCODE_BACK) return true;
        int vk = KeyMap.toVK(keyCode);
        if (vk != 0) {
            final int shift = KeyMap.shiftFlags(e);
            queueEvent(() -> KaMNative.key(1, vk, shift));
            return true;
        }
        return super.onKeyUp(keyCode, e);
    }

    // ---------- Soft keyboard ----------

    @Override
    public boolean onCheckIsTextEditor() {
        return true;
    }

    @Override
    public InputConnection onCreateInputConnection(EditorInfo outAttrs) {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS;
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_ACTION_DONE;
        return new BaseInputConnection(this, false) {
            @Override
            public boolean commitText(CharSequence text, int newCursorPosition) {
                String s = text.toString();
                for (int i = 0; i < s.length(); ) {
                    final int cp = s.codePointAt(i);
                    i += Character.charCount(cp);
                    queueEvent(() -> KaMNative.charInput(cp));
                }
                return true;
            }

            @Override
            public boolean deleteSurroundingText(int beforeLength, int afterLength) {
                for (int i = 0; i < beforeLength; i++) pressKey(8);
                return true;
            }

            @Override
            public boolean performEditorAction(int actionCode) {
                pressKey(13);
                return true;
            }

            @Override
            public boolean sendKeyEvent(KeyEvent event) {
                if (event.getAction() == KeyEvent.ACTION_DOWN) return onKeyDown(event.getKeyCode(), event);
                if (event.getAction() == KeyEvent.ACTION_UP) return onKeyUp(event.getKeyCode(), event);
                return true;
            }
        };
    }

    private void pressKey(int vk) {
        queueEvent(() -> {
            KaMNative.key(0, vk, 0);
            KaMNative.charInput(vk);
            KaMNative.key(1, vk, 0);
        });
    }
}
