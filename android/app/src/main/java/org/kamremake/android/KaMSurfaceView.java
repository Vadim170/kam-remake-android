package org.kamremake.android;

import android.content.Context;
import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLSurface;
import android.util.Log;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

import java.util.ArrayDeque;

/**
 * SurfaceView with its own GLES2 render thread (instead of GLSurfaceView).
 * The game engine runs on this thread and needs a large stack: the desktop build uses 8 MB with 32-bit
 * frames and some algorithms (e.g. terrain flood fill on big maps) recurse deeply. GLSurfaceView's thread
 * has the default ~1 MB stack which can't be changed.
 * The EGL context is kept while the app is paused, so textures survive going to background.
 */
abstract class KaMSurfaceView extends SurfaceView implements SurfaceHolder.Callback {
    private static final String TAG = "KaMRender";
    private static final long RENDER_THREAD_STACK = 128L << 20;

    private final Object lock = new Object();
    private final ArrayDeque<Runnable> events = new ArrayDeque<>();
    private SurfaceHolder holder;
    private boolean hasSurface;
    private boolean surfaceReleased = true;
    private boolean paused;
    private boolean exiting;
    private int width, height;
    private boolean sizeChanged;

    KaMSurfaceView(Context context) {
        super(context);
        getHolder().addCallback(this);
        Thread t = new Thread(null, this::renderLoop, "KaMRender", RENDER_THREAD_STACK);
        t.start();
    }

    /** Called on the render thread when the surface size is known or changed */
    protected abstract void onSurfaceChanged(int width, int height);

    /** Called on the render thread for every frame */
    protected abstract void onDrawFrame();

    void queueEvent(Runnable r) {
        synchronized (lock) {
            events.add(r);
            lock.notifyAll();
        }
    }

    void onPause() {
        synchronized (lock) {
            paused = true;
            lock.notifyAll();
        }
    }

    void onResume() {
        synchronized (lock) {
            paused = false;
            lock.notifyAll();
        }
    }

    void exit() {
        synchronized (lock) {
            exiting = true;
            lock.notifyAll();
        }
    }

    // ---------- SurfaceHolder.Callback (UI thread) ----------

    @Override
    public void surfaceCreated(SurfaceHolder h) {
        synchronized (lock) {
            holder = h;
            hasSurface = true;
            lock.notifyAll();
        }
    }

    @Override
    public void surfaceChanged(SurfaceHolder h, int format, int w, int hgt) {
        synchronized (lock) {
            width = w;
            height = hgt;
            sizeChanged = true;
            lock.notifyAll();
        }
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder h) {
        synchronized (lock) {
            hasSurface = false;
            lock.notifyAll();
            // The render thread must stop using the surface before it goes away
            while (!surfaceReleased && !exiting) {
                try {
                    lock.wait();
                } catch (InterruptedException e) {
                    return;
                }
            }
        }
    }

    // ---------- Render thread ----------

    private void renderLoop() {
        EGLDisplay display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
        int[] ver = new int[2];
        EGL14.eglInitialize(display, ver, 0, ver, 1);
        int[] attribs = {
                EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_DEPTH_SIZE, 16, EGL14.EGL_STENCIL_SIZE, 8,
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT, EGL14.EGL_NONE};
        EGLConfig[] configs = new EGLConfig[1];
        int[] num = new int[1];
        EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, num, 0);
        EGLConfig config = configs[0];
        EGLContext context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT,
                new int[]{EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE}, 0);
        EGLSurface surface = EGL14.EGL_NO_SURFACE;

        while (true) {
            Runnable event = null;
            boolean draw = false, resize = false;
            int w = 0, h = 0;
            SurfaceHolder sh = null;
            synchronized (lock) {
                if (exiting) break;
                // Release the window surface when it's gone (context is kept)
                if (!hasSurface && surface != EGL14.EGL_NO_SURFACE) {
                    EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, context);
                    EGL14.eglDestroySurface(display, surface);
                    surface = EGL14.EGL_NO_SURFACE;
                }
                if (surface == EGL14.EGL_NO_SURFACE && !surfaceReleased) {
                    surfaceReleased = true;
                    lock.notifyAll();
                }
                if (hasSurface && surface == EGL14.EGL_NO_SURFACE) {
                    sh = holder;
                    surfaceReleased = false;
                }
                if (!events.isEmpty()) {
                    event = events.poll();
                } else if (hasSurface && !paused && width > 0) {
                    draw = true;
                    if (sizeChanged) {
                        resize = true;
                        sizeChanged = false;
                        w = width;
                        h = height;
                    }
                } else if (sh == null) {
                    try {
                        lock.wait();
                    } catch (InterruptedException e) {
                        break;
                    }
                    continue;
                }
            }

            if (sh != null) {
                surface = EGL14.eglCreateWindowSurface(display, config, sh.getSurface(), new int[]{EGL14.EGL_NONE}, 0);
                if (surface == null || surface == EGL14.EGL_NO_SURFACE) {
                    Log.e(TAG, "eglCreateWindowSurface failed: " + EGL14.eglGetError());
                    surface = EGL14.EGL_NO_SURFACE;
                } else {
                    EGL14.eglMakeCurrent(display, surface, surface, context);
                }
            }

            if (event != null) {
                // Input and lifecycle events are delivered to the engine, which needs the GL context current
                if (EGL14.eglGetCurrentContext().equals(EGL14.EGL_NO_CONTEXT))
                    EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, context);
                event.run();
                continue;
            }

            if (draw && surface != EGL14.EGL_NO_SURFACE) {
                if (resize) onSurfaceChanged(w, h);
                onDrawFrame();
                EGL14.eglSwapBuffers(display, surface);
            }
        }

        synchronized (lock) {
            surfaceReleased = true;
            lock.notifyAll();
        }
    }
}
