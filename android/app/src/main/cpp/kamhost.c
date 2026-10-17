// JNI glue between the Java activity and the KaM Remake engine (libkamcore.so, Free Pascal)
#include <android/log.h>
#include <dlfcn.h>
#include <jni.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <ucontext.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>
#include <time.h>
#include <unwind.h>
#include <link.h>

#define LOG(...) __android_log_print(ANDROID_LOG_INFO, "KaMHost", __VA_ARGS__)

typedef struct {
  void (*ShowMessage)(const char *title, const char *text);
  void (*ClipboardSet)(const char *text);
  const char *(*ClipboardGet)(void);
  void (*OpenURL)(const char *url);
  void (*Quit)(void);
  void (*PlayVideo)(const char *path, int volume, int stretch);
  void (*StopVideo)(void);
} kam_host_callbacks;

// Exported by libkamcore.so
extern void kam_set_callbacks(kam_host_callbacks *cb);
extern int kam_init(const char *dataDir, int width, int height);
extern void kam_frame(void);
extern void kam_resize(int width, int height);
extern void kam_pause(void);
extern void kam_resume(void);
extern void kam_shutdown(void);
extern void kam_touch(int action, int count, float x0, float y0, float x1, float y1);
extern void kam_mouse(int action, int button, int x, int y);
extern void kam_wheel(int steps, int x, int y);
extern void kam_key(int action, int vk, int shift);
extern void kam_char(int ch);
extern void kam_back(void);
extern int kam_text_input_active(void);
extern void kam_video_finished(void);
extern int kam_in_game(void);
extern int kam_text_input_bottom(void);
extern int kam_text_field_tapped(void);
extern void kam_selftest(const char *mode);

static JavaVM *g_vm;
static jclass g_cls;
static jmethodID m_showMessage, m_clipSet, m_clipGet, m_openUrl, m_quit, m_playVideo, m_stopVideo;
static char *g_clipboard;

static JNIEnv *get_env(void) {
  JNIEnv *env = NULL;
  if ((*g_vm)->GetEnv(g_vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK)
    (*g_vm)->AttachCurrentThread(g_vm, &env, NULL);
  return env;
}

static jstring jstr(JNIEnv *env, const char *s) { return (*env)->NewStringUTF(env, s ? s : ""); }

static void cb_show_message(const char *title, const char *text) {
  JNIEnv *env = get_env();
  jstring t = jstr(env, title), x = jstr(env, text);
  (*env)->CallStaticVoidMethod(env, g_cls, m_showMessage, t, x);
  (*env)->DeleteLocalRef(env, t);
  (*env)->DeleteLocalRef(env, x);
}

static void cb_clipboard_set(const char *text) {
  JNIEnv *env = get_env();
  jstring t = jstr(env, text);
  (*env)->CallStaticVoidMethod(env, g_cls, m_clipSet, t);
  (*env)->DeleteLocalRef(env, t);
}

static const char *cb_clipboard_get(void) {
  JNIEnv *env = get_env();
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, g_cls, m_clipGet);
  free(g_clipboard);
  g_clipboard = NULL;
  if (s) {
    const char *c = (*env)->GetStringUTFChars(env, s, NULL);
    g_clipboard = strdup(c);
    (*env)->ReleaseStringUTFChars(env, s, c);
    (*env)->DeleteLocalRef(env, s);
  }
  return g_clipboard ? g_clipboard : "";
}

static void cb_open_url(const char *url) {
  JNIEnv *env = get_env();
  jstring t = jstr(env, url);
  (*env)->CallStaticVoidMethod(env, g_cls, m_openUrl, t);
  (*env)->DeleteLocalRef(env, t);
}

static void cb_quit(void) {
  JNIEnv *env = get_env();
  (*env)->CallStaticVoidMethod(env, g_cls, m_quit);
}

static void cb_play_video(const char *path, int volume, int stretch) {
  JNIEnv *env = get_env();
  jstring t = jstr(env, path);
  (*env)->CallStaticVoidMethod(env, g_cls, m_playVideo, t, volume, stretch ? JNI_TRUE : JNI_FALSE);
  (*env)->DeleteLocalRef(env, t);
}

static void cb_stop_video(void) {
  JNIEnv *env = get_env();
  (*env)->CallStaticVoidMethod(env, g_cls, m_stopVideo);
}

// ---------- Crash reporting: logs the faulting address and stack as library+offset ----------

static struct sigaction g_old_sa[32];

static void log_addr(const char *what, uintptr_t pc) {
  Dl_info info;
  if (dladdr((void *)pc, &info) && info.dli_fname) {
    const char *name = strrchr(info.dli_fname, '/');
    __android_log_print(ANDROID_LOG_ERROR, "KaMCrash", "%s %s+0x%lx (%s)", what, name ? name + 1 : info.dli_fname,
                        (unsigned long)(pc - (uintptr_t)info.dli_fbase), info.dli_sname ? info.dli_sname : "?");
  } else {
    __android_log_print(ANDROID_LOG_ERROR, "KaMCrash", "%s 0x%lx", what, (unsigned long)pc);
  }
}

typedef struct { int n; } unwind_state;

static _Unwind_Reason_Code unwind_cb(struct _Unwind_Context *ctx, void *arg) {
  unwind_state *st = (unwind_state *)arg;
  uintptr_t pc = _Unwind_GetIP(ctx);
  if (pc) log_addr("  at", pc);
  return ++st->n < 40 ? _URC_NO_REASON : _URC_END_OF_STACK;
}

static uintptr_t g_core_lo, g_core_hi;

static int phdr_cb(struct dl_phdr_info *info, size_t size, void *data) {
  (void)size; (void)data;
  if (!info->dlpi_name || !strstr(info->dlpi_name, "libkamcore.so")) return 0;
  for (int i = 0; i < info->dlpi_phnum; i++) {
    const ElfW(Phdr) *ph = &info->dlpi_phdr[i];
    if (ph->p_type == PT_LOAD && (ph->p_flags & PF_X)) {
      g_core_lo = info->dlpi_addr + ph->p_vaddr;
      g_core_hi = g_core_lo + ph->p_memsz;
    }
  }
  return 1;
}

// Heuristic: values on the stack that point into engine code are likely return addresses
static void scan_stack(uintptr_t sp) {
  if (!g_core_lo) dl_iterate_phdr(phdr_cb, NULL);
  if (!g_core_lo) return;
  int found = 0;
  for (uintptr_t *p = (uintptr_t *)sp; p < (uintptr_t *)(sp + 256 * 1024) && found < 30; p++) {
    uintptr_t v = *p;
    if (v >= g_core_lo && v < g_core_hi) {
      log_addr("  stk", v);
      found++;
    }
  }
}

// ---------- Stall sampler: logs the engine stack when a frame takes too long ----------

static volatile pthread_t g_frame_thread;
static volatile long long g_frame_start_ms;

static long long mono_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void stall_handler(int sig, siginfo_t *info, void *ucv) {
  (void)sig; (void)info;
  ucontext_t *uc = (ucontext_t *)ucv;
  __android_log_print(ANDROID_LOG_WARN, "KaMCrash", "STALL frame running %lld ms", mono_ms() - g_frame_start_ms);
  log_addr("STALL pc", (uintptr_t)uc->uc_mcontext.pc);
  log_addr("STALL lr", (uintptr_t)uc->uc_mcontext.regs[30]);
  scan_stack((uintptr_t)uc->uc_mcontext.sp);
}

static void *watchdog_thread(void *arg) {
  (void)arg;
  long long last_sample = 0;
  for (;;) {
    sleep(1);
    long long start = g_frame_start_ms;
    long long now = mono_ms();
    if (start && now - start > 3000 && now - last_sample > 3000) {
      last_sample = now;
      pthread_kill(g_frame_thread, SIGURG);
    }
  }
  return NULL;
}

static void crash_handler(int sig, siginfo_t *info, void *ucv) {
  ucontext_t *uc = (ucontext_t *)ucv;
  __android_log_print(ANDROID_LOG_ERROR, "KaMCrash", "signal %d, fault addr %p", sig, info->si_addr);
  log_addr("pc", (uintptr_t)uc->uc_mcontext.pc);
  log_addr("lr", (uintptr_t)uc->uc_mcontext.regs[30]);
  // Walk the frame pointer chain (FPC code keeps frame pointers)
  uintptr_t fp = (uintptr_t)uc->uc_mcontext.regs[29];
  for (int i = 0; i < 40 && fp && (fp & 7) == 0; i++) {
    uintptr_t *frame = (uintptr_t *)fp;
    if (!frame[1]) break;
    log_addr("  fp", frame[1]);
    if (frame[0] <= fp) break;
    fp = frame[0];
  }
  unwind_state st = {0};
  _Unwind_Backtrace(unwind_cb, &st);
  scan_stack((uintptr_t)uc->uc_mcontext.sp);
  sigaction(sig, &g_old_sa[sig], NULL);
  raise(sig);
}

static void install_crash_handler(void) {
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_sigaction = crash_handler;
  sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
  int sigs[] = {SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT};
  for (unsigned i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) sigaction(sigs[i], &sa, &g_old_sa[sigs[i]]);

  struct sigaction ss;
  memset(&ss, 0, sizeof(ss));
  ss.sa_sigaction = stall_handler;
  ss.sa_flags = SA_SIGINFO | SA_RESTART;
  sigaction(SIGURG, &ss, NULL);
  pthread_t t;
  pthread_create(&t, NULL, watchdog_thread, NULL);
  pthread_detach(t);
}

// ---------- stdout/stderr -> logcat (gl4es and RTL write diagnostics there) ----------

static int g_stdio_pipe[2];

static void *stdio_thread(void *arg) {
  (void)arg;
  char buf[1024];
  size_t len = 0;
  ssize_t r;
  while ((r = read(g_stdio_pipe[0], buf + len, sizeof(buf) - 1 - len)) > 0) {
    len += (size_t)r;
    buf[len] = 0;
    char *start = buf, *nl;
    while ((nl = strchr(start, '\n')) != NULL) {
      *nl = 0;
      if (nl > start) __android_log_write(ANDROID_LOG_INFO, "KaMStdout", start);
      start = nl + 1;
    }
    len = strlen(start);
    memmove(buf, start, len);
    if (len >= sizeof(buf) - 1) {
      buf[len] = 0;
      __android_log_write(ANDROID_LOG_INFO, "KaMStdout", buf);
      len = 0;
    }
  }
  return NULL;
}

static void redirect_stdio(void) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  setvbuf(stderr, NULL, _IONBF, 0);
  if (pipe(g_stdio_pipe) != 0) return;
  dup2(g_stdio_pipe[1], 1);
  dup2(g_stdio_pipe[1], 2);
  pthread_t t;
  pthread_create(&t, NULL, stdio_thread, NULL);
  pthread_detach(t);
}

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {
  (void)reserved;
  g_vm = vm;
  install_crash_handler();
  redirect_stdio();
  JNIEnv *env;
  if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return -1;
  jclass c = (*env)->FindClass(env, "org/kamremake/android/KaMNative");
  g_cls = (jclass)(*env)->NewGlobalRef(env, c);
  m_showMessage = (*env)->GetStaticMethodID(env, g_cls, "onShowMessage", "(Ljava/lang/String;Ljava/lang/String;)V");
  m_clipSet = (*env)->GetStaticMethodID(env, g_cls, "onClipboardSet", "(Ljava/lang/String;)V");
  m_clipGet = (*env)->GetStaticMethodID(env, g_cls, "onClipboardGet", "()Ljava/lang/String;");
  m_openUrl = (*env)->GetStaticMethodID(env, g_cls, "onOpenURL", "(Ljava/lang/String;)V");
  m_quit = (*env)->GetStaticMethodID(env, g_cls, "onQuit", "()V");
  m_playVideo = (*env)->GetStaticMethodID(env, g_cls, "onPlayVideo", "(Ljava/lang/String;IZ)V");
  m_stopVideo = (*env)->GetStaticMethodID(env, g_cls, "onStopVideo", "()V");

  static kam_host_callbacks cb = {cb_show_message, cb_clipboard_set, cb_clipboard_get, cb_open_url, cb_quit, cb_play_video, cb_stop_video};
  kam_set_callbacks(&cb);
  return JNI_VERSION_1_6;
}

#define JNI(ret, name) JNIEXPORT ret JNICALL Java_org_kamremake_android_KaMNative_##name

JNI(jboolean, init)(JNIEnv *env, jclass cls, jstring dataDir, jint w, jint h) {
  (void)cls;
  const char *d = (*env)->GetStringUTFChars(env, dataDir, NULL);
  int ok = kam_init(d, w, h);
  (*env)->ReleaseStringUTFChars(env, dataDir, d);
  return ok ? JNI_TRUE : JNI_FALSE;
}

JNI(void, frame)(JNIEnv *env, jclass cls) {
  (void)env; (void)cls;
  g_frame_thread = pthread_self();
  g_frame_start_ms = mono_ms();
  kam_frame();
  g_frame_start_ms = 0;
}
JNI(void, resize)(JNIEnv *env, jclass cls, jint w, jint h) { (void)env; (void)cls; kam_resize(w, h); }
JNI(void, pause)(JNIEnv *env, jclass cls) { (void)env; (void)cls; kam_pause(); }
JNI(void, resume)(JNIEnv *env, jclass cls) { (void)env; (void)cls; kam_resume(); }
JNI(void, shutdown)(JNIEnv *env, jclass cls) { (void)env; (void)cls; kam_shutdown(); }
JNI(void, touch)(JNIEnv *env, jclass cls, jint action, jint count, jfloat x0, jfloat y0, jfloat x1, jfloat y1) {
  (void)env; (void)cls;
  kam_touch(action, count, x0, y0, x1, y1);
}
JNI(void, mouse)(JNIEnv *env, jclass cls, jint action, jint button, jint x, jint y) { (void)env; (void)cls; kam_mouse(action, button, x, y); }
JNI(void, wheel)(JNIEnv *env, jclass cls, jint steps, jint x, jint y) { (void)env; (void)cls; kam_wheel(steps, x, y); }
JNI(void, key)(JNIEnv *env, jclass cls, jint action, jint vk, jint shift) { (void)env; (void)cls; kam_key(action, vk, shift); }
JNI(void, charInput)(JNIEnv *env, jclass cls, jint ch) { (void)env; (void)cls; kam_char(ch); }
JNI(void, back)(JNIEnv *env, jclass cls) { (void)env; (void)cls; kam_back(); }
JNI(jboolean, textInputActive)(JNIEnv *env, jclass cls) { (void)env; (void)cls; return kam_text_input_active() ? JNI_TRUE : JNI_FALSE; }
JNI(void, videoFinished)(JNIEnv *env, jclass cls) { (void)env; (void)cls; kam_video_finished(); }
JNI(jboolean, inGame)(JNIEnv *env, jclass cls) { (void)env; (void)cls; return kam_in_game() ? JNI_TRUE : JNI_FALSE; }
JNI(jint, textInputBottom)(JNIEnv *env, jclass cls) { (void)env; (void)cls; return kam_text_input_bottom(); }
JNI(jboolean, textFieldTapped)(JNIEnv *env, jclass cls) { (void)env; (void)cls; return kam_text_field_tapped() ? JNI_TRUE : JNI_FALSE; }
JNI(void, selfTest)(JNIEnv *env, jclass cls, jstring mode) {
  (void)cls;
  const char *m = (*env)->GetStringUTFChars(env, mode, NULL);
  kam_selftest(m);
  (*env)->ReleaseStringUTFChars(env, mode, m);
}
