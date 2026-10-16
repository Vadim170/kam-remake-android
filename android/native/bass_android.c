// Minimal BASS-compatible audio library for the Android port of KaM Remake.
// Implements the subset of the BASS API used by KM_Music (music tracks and briefing voice files)
// on top of OpenAL Soft. Decoders: minimp3 (MP1/MP2/MP3), libvorbisfile (OGG), PCM WAV.
// All OpenAL calls are made from a single streaming thread with its own device/context,
// so it never interferes with the OpenAL context used by the game sound effects.

#include <AL/al.h>
#include <AL/alc.h>
#include <AL/alext.h>
#include <android/log.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include <unistd.h>

#define MINIMP3_IMPLEMENTATION
#include "minimp3_ex.h"
#include <vorbis/vorbisfile.h>

#define LOG(...) __android_log_print(ANDROID_LOG_INFO, "KaMBass", __VA_ARGS__)

typedef uint32_t DWORD;
typedef int32_t BOOL;
typedef uint64_t QWORD;

#define BASS_OK 0
#define BASS_ERROR_MEM 1
#define BASS_ERROR_FILEOPEN 2
#define BASS_ERROR_HANDLE 5
#define BASS_ERROR_INIT 8
#define BASS_ERROR_ALREADY 14
#define BASS_ERROR_FILEFORM 41
#define BASS_ERROR_UNKNOWN -1

#define BASS_STREAM_AUTOFREE 0x40000
#define BASS_UNICODE 0x80000000u

#define BASS_ACTIVE_STOPPED 0
#define BASS_ACTIVE_PLAYING 1
#define BASS_ACTIVE_PAUSED 3

#define BASS_ATTRIB_VOL 2

#define MAX_STREAMS 8
#define NUM_BUFFERS 4
#define BUFFER_FRAMES 8192

typedef enum { DEC_NONE, DEC_MP3, DEC_OGG, DEC_WAV } dec_kind;

typedef struct {
  dec_kind kind;
  int channels;
  int rate;
  mp3dec_ex_t mp3;
  OggVorbis_File ogg;
  FILE *wav;
  long wav_data_start;
  long wav_data_size;
  long wav_data_read;
  int wav_bits;
} decoder;

typedef enum { ST_FREE, ST_STOPPED, ST_PLAYING, ST_PAUSED } stream_state;

typedef struct {
  stream_state state;
  uint32_t gen;
  DWORD flags;
  decoder dec;
  int eof;
  // Pending requests from API thread, applied by the streaming thread
  int req_restart;
  int req_free;
  // Volume and slide
  float volume;
  float slide_from, slide_to;
  uint64_t slide_start_ms;
  uint32_t slide_time_ms;
  int sliding;
  // OpenAL objects (owned by streaming thread)
  ALuint source;
  ALuint buffers[NUM_BUFFERS];
  int al_ready;
} stream;

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t g_thread;
static volatile int g_running;
static int g_inited;
static ALCdevice *g_device;
static ALCcontext *g_context;
static stream g_streams[MAX_STREAMS];
static __thread int g_error;
static int16_t g_pcm[BUFFER_FRAMES * 2];

static PFNALCSETTHREADCONTEXTPROC p_alcSetThreadContext;

static uint64_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// ---------- Decoders ----------

static int has_ext(const char *path, const char *ext) {
  size_t lp = strlen(path), le = strlen(ext);
  return lp >= le && strcasecmp(path + lp - le, ext) == 0;
}

static int wav_open(decoder *d, const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) return 0;
  char id[4];
  uint32_t size;
  if (fread(id, 1, 4, f) != 4 || memcmp(id, "RIFF", 4) != 0) goto fail;
  fseek(f, 4, SEEK_CUR);
  if (fread(id, 1, 4, f) != 4 || memcmp(id, "WAVE", 4) != 0) goto fail;
  int got_fmt = 0;
  while (fread(id, 1, 4, f) == 4 && fread(&size, 4, 1, f) == 1) {
    if (memcmp(id, "fmt ", 4) == 0) {
      uint16_t fmt, ch, bits;
      uint32_t rate;
      if (fread(&fmt, 2, 1, f) != 1 || fread(&ch, 2, 1, f) != 1 || fread(&rate, 4, 1, f) != 1) goto fail;
      fseek(f, 6, SEEK_CUR);
      if (fread(&bits, 2, 1, f) != 1) goto fail;
      fseek(f, (long)size - 16, SEEK_CUR);
      if (fmt != 1 || (bits != 8 && bits != 16) || ch < 1 || ch > 2) goto fail;
      d->channels = ch;
      d->rate = (int)rate;
      d->wav_bits = bits;
      got_fmt = 1;
    } else if (memcmp(id, "data", 4) == 0) {
      if (!got_fmt) goto fail;
      d->wav = f;
      d->wav_data_start = ftell(f);
      d->wav_data_size = size;
      d->wav_data_read = 0;
      return 1;
    } else {
      fseek(f, (long)size + (size & 1), SEEK_CUR);
    }
  }
fail:
  fclose(f);
  return 0;
}

static int dec_open(decoder *d, const char *path) {
  memset(d, 0, sizeof(*d));
  if (has_ext(path, ".ogg") || has_ext(path, ".oga")) {
    if (ov_fopen(path, &d->ogg) != 0) return 0;
    vorbis_info *vi = ov_info(&d->ogg, -1);
    d->channels = vi->channels;
    d->rate = (int)vi->rate;
    d->kind = DEC_OGG;
    return d->channels == 1 || d->channels == 2 ? 1 : (ov_clear(&d->ogg), 0);
  }
  if (has_ext(path, ".wav")) {
    if (!wav_open(d, path)) return 0;
    d->kind = DEC_WAV;
    return 1;
  }
  // MP1/MP2/MP3
  if (mp3dec_ex_open(&d->mp3, path, MP3D_SEEK_TO_SAMPLE) != 0) return 0;
  d->channels = d->mp3.info.channels;
  d->rate = d->mp3.info.hz;
  d->kind = DEC_MP3;
  if (d->channels < 1 || d->channels > 2 || d->rate <= 0) {
    mp3dec_ex_close(&d->mp3);
    return 0;
  }
  return 1;
}

static void dec_close(decoder *d) {
  switch (d->kind) {
    case DEC_MP3: mp3dec_ex_close(&d->mp3); break;
    case DEC_OGG: ov_clear(&d->ogg); break;
    case DEC_WAV: fclose(d->wav); break;
    default: break;
  }
  d->kind = DEC_NONE;
}

static void dec_rewind(decoder *d) {
  switch (d->kind) {
    case DEC_MP3: mp3dec_ex_seek(&d->mp3, 0); break;
    case DEC_OGG: ov_pcm_seek(&d->ogg, 0); break;
    case DEC_WAV: fseek(d->wav, d->wav_data_start, SEEK_SET); d->wav_data_read = 0; break;
    default: break;
  }
}

// Returns number of frames decoded into out (interleaved int16)
static int dec_read(decoder *d, int16_t *out, int frames) {
  int want = frames * d->channels;
  int got = 0;
  switch (d->kind) {
    case DEC_MP3:
      got = (int)mp3dec_ex_read(&d->mp3, out, (size_t)want);
      break;
    case DEC_OGG: {
      char *p = (char *)out;
      int bytes = want * 2;
      while (bytes > 0) {
        int section;
        long r = ov_read(&d->ogg, p, bytes, 0, 2, 1, &section);
        if (r <= 0) break;
        p += r;
        bytes -= (int)r;
      }
      got = (int)((p - (char *)out) / 2);
      break;
    }
    case DEC_WAV: {
      long left = d->wav_data_size - d->wav_data_read;
      if (d->wav_bits == 16) {
        long bytes = (long)want * 2;
        if (bytes > left) bytes = left;
        size_t r = fread(out, 1, (size_t)bytes, d->wav);
        d->wav_data_read += (long)r;
        got = (int)(r / 2);
      } else {
        long bytes = want;
        if (bytes > left) bytes = left;
        uint8_t *tmp = (uint8_t *)out + want; // Upper half of out is free for 8 bit data
        size_t r = fread(tmp, 1, (size_t)bytes, d->wav);
        d->wav_data_read += (long)r;
        for (size_t i = 0; i < r; i++) out[i] = (int16_t)(((int)tmp[i] - 128) << 8);
        got = (int)r;
      }
      break;
    }
    default:
      break;
  }
  return got / d->channels;
}

// ---------- Streaming thread ----------

static float current_volume(stream *s, uint64_t t) {
  if (!s->sliding) return s->volume;
  uint64_t el = t - s->slide_start_ms;
  if (s->slide_time_ms == 0 || el >= s->slide_time_ms) {
    s->sliding = 0;
    s->volume = s->slide_to;
    return s->volume;
  }
  float k = (float)el / (float)s->slide_time_ms;
  s->volume = s->slide_from + (s->slide_to - s->slide_from) * k;
  return s->volume;
}

static int fill_buffer(stream *s, ALuint buf) {
  if (s->eof) return 0;
  int frames = dec_read(&s->dec, g_pcm, BUFFER_FRAMES);
  if (frames <= 0) {
    s->eof = 1;
    return 0;
  }
  if (frames < BUFFER_FRAMES) s->eof = 1;
  ALenum fmt = s->dec.channels == 2 ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16;
  alBufferData(buf, fmt, g_pcm, frames * s->dec.channels * 2, s->dec.rate);
  return 1;
}

static void al_release(stream *s) {
  if (!s->al_ready) return;
  alSourceStop(s->source);
  alSourcei(s->source, AL_BUFFER, 0);
  alDeleteSources(1, &s->source);
  alDeleteBuffers(NUM_BUFFERS, s->buffers);
  s->al_ready = 0;
}

static void stream_release(stream *s) {
  al_release(s);
  dec_close(&s->dec);
  s->state = ST_FREE;
  s->gen++;
}

static void restart_stream(stream *s) {
  if (!s->al_ready) {
    alGenSources(1, &s->source);
    alGenBuffers(NUM_BUFFERS, s->buffers);
    alSourcef(s->source, AL_ROLLOFF_FACTOR, 0.0f);
    alSourcei(s->source, AL_SOURCE_RELATIVE, AL_TRUE);
    s->al_ready = 1;
  }
  alSourceStop(s->source);
  alSourcei(s->source, AL_BUFFER, 0);
  dec_rewind(&s->dec);
  s->eof = 0;
  int queued = 0;
  for (int i = 0; i < NUM_BUFFERS; i++) {
    if (!fill_buffer(s, s->buffers[i])) break;
    queued++;
  }
  if (queued > 0) {
    alSourceQueueBuffers(s->source, queued, s->buffers);
    alSourcePlay(s->source);
  }
}

static void service_stream(stream *s, uint64_t t) {
  if (s->req_free) {
    stream_release(s);
    return;
  }
  if (s->req_restart) {
    s->req_restart = 0;
    restart_stream(s);
  }
  if (!s->al_ready) return;

  alSourcef(s->source, AL_GAIN, current_volume(s, t));

  ALint st;
  alGetSourcei(s->source, AL_SOURCE_STATE, &st);
  if (s->state == ST_PAUSED) {
    if (st == AL_PLAYING) alSourcePause(s->source);
    return;
  }
  if (s->state != ST_PLAYING) {
    if (st == AL_PLAYING || st == AL_PAUSED) alSourceStop(s->source);
    return;
  }

  ALint processed = 0;
  alGetSourcei(s->source, AL_BUFFERS_PROCESSED, &processed);
  while (processed-- > 0) {
    ALuint buf;
    alSourceUnqueueBuffers(s->source, 1, &buf);
    if (fill_buffer(s, buf)) alSourceQueueBuffers(s->source, 1, &buf);
  }

  ALint queued = 0;
  alGetSourcei(s->source, AL_BUFFERS_QUEUED, &queued);
  if (st != AL_PLAYING) {
    if (queued > 0) {
      alSourcePlay(s->source); // Resume after pause or buffer underrun
    } else if (s->eof) {
      // Track finished
      s->state = ST_STOPPED;
      if (s->flags & BASS_STREAM_AUTOFREE) stream_release(s);
    }
  }
}

static void *stream_thread(void *arg) {
  (void)arg;
  if (p_alcSetThreadContext) p_alcSetThreadContext(g_context);
  else alcMakeContextCurrent(g_context);
  while (g_running) {
    uint64_t t = now_ms();
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < MAX_STREAMS; i++)
      if (g_streams[i].state != ST_FREE) service_stream(&g_streams[i], t);
    pthread_mutex_unlock(&g_lock);
    usleep(10000);
  }
  pthread_mutex_lock(&g_lock);
  for (int i = 0; i < MAX_STREAMS; i++)
    if (g_streams[i].state != ST_FREE) stream_release(&g_streams[i]);
  pthread_mutex_unlock(&g_lock);
  if (p_alcSetThreadContext) p_alcSetThreadContext(NULL);
  return NULL;
}

// ---------- Handles ----------

static DWORD make_handle(int idx) { return ((g_streams[idx].gen & 0xFFFF) << 8) | (DWORD)(idx + 1); }

static stream *get_stream(DWORD h) {
  int idx = (int)(h & 0xFF) - 1;
  if (idx < 0 || idx >= MAX_STREAMS) return NULL;
  stream *s = &g_streams[idx];
  if (s->state == ST_FREE || s->req_free || ((s->gen & 0xFFFF) != (h >> 8))) return NULL;
  return s;
}

// ---------- Public API (subset of BASS) ----------

#define API __attribute__((visibility("default")))

API BOOL BASS_SetConfig(DWORD option, DWORD value) {
  (void)option; (void)value;
  g_error = BASS_OK;
  return 1;
}

API DWORD BASS_GetConfig(DWORD option) {
  (void)option;
  return 0;
}

API DWORD BASS_GetVersion(void) { return 0x02041000; }

API int BASS_ErrorGetCode(void) { return g_error; }

API BOOL BASS_Init(int device, DWORD freq, DWORD flags, void *win, void *clsid) {
  (void)device; (void)flags; (void)win; (void)clsid;
  if (g_inited) {
    g_error = BASS_ERROR_ALREADY;
    return 0;
  }
  g_device = alcOpenDevice(NULL);
  if (!g_device) {
    LOG("alcOpenDevice failed");
    g_error = BASS_ERROR_INIT;
    return 0;
  }
  ALCint attrs[] = {ALC_FREQUENCY, (ALCint)(freq ? freq : 44100), 0};
  g_context = alcCreateContext(g_device, attrs);
  if (!g_context) {
    alcCloseDevice(g_device);
    g_device = NULL;
    g_error = BASS_ERROR_INIT;
    return 0;
  }
  if (alcIsExtensionPresent(NULL, "ALC_EXT_thread_local_context"))
    p_alcSetThreadContext = (PFNALCSETTHREADCONTEXTPROC)alcGetProcAddress(NULL, "alcSetThreadContext");
  memset(g_streams, 0, sizeof(g_streams));
  g_running = 1;
  if (pthread_create(&g_thread, NULL, stream_thread, NULL) != 0) {
    alcDestroyContext(g_context);
    alcCloseDevice(g_device);
    g_error = BASS_ERROR_INIT;
    return 0;
  }
  g_inited = 1;
  g_error = BASS_OK;
  LOG("Music output initialized");
  return 1;
}

API BOOL BASS_Free(void) {
  if (!g_inited) {
    g_error = BASS_ERROR_INIT;
    return 0;
  }
  g_running = 0;
  pthread_join(g_thread, NULL);
  alcDestroyContext(g_context);
  alcCloseDevice(g_device);
  g_context = NULL;
  g_device = NULL;
  g_inited = 0;
  g_error = BASS_OK;
  return 1;
}

API BOOL BASS_Stop(void) {
  pthread_mutex_lock(&g_lock);
  for (int i = 0; i < MAX_STREAMS; i++)
    if (g_streams[i].state == ST_PLAYING) g_streams[i].state = ST_PAUSED;
  pthread_mutex_unlock(&g_lock);
  g_error = BASS_OK;
  return 1;
}

API BOOL BASS_Start(void) {
  g_error = BASS_OK;
  return 1;
}

static char *utf16_to_utf8(const uint16_t *w) {
  size_t n = 0;
  while (w[n]) n++;
  char *out = malloc(n * 3 + 1), *p = out;
  for (size_t i = 0; i < n; i++) {
    uint32_t c = w[i];
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < n) {
      c = 0x10000 + ((c - 0xD800) << 10) + (w[i + 1] - 0xDC00);
      i++;
    }
    if (c < 0x80) *p++ = (char)c;
    else if (c < 0x800) { *p++ = (char)(0xC0 | (c >> 6)); *p++ = (char)(0x80 | (c & 0x3F)); }
    else if (c < 0x10000) { *p++ = (char)(0xE0 | (c >> 12)); *p++ = (char)(0x80 | ((c >> 6) & 0x3F)); *p++ = (char)(0x80 | (c & 0x3F)); }
    else { *p++ = (char)(0xF0 | (c >> 18)); *p++ = (char)(0x80 | ((c >> 12) & 0x3F)); *p++ = (char)(0x80 | ((c >> 6) & 0x3F)); *p++ = (char)(0x80 | (c & 0x3F)); }
  }
  *p = 0;
  return out;
}

API DWORD BASS_StreamCreateFile(BOOL mem, const void *file, QWORD offset, QWORD length, DWORD flags) {
  (void)offset; (void)length;
  if (!g_inited) {
    g_error = BASS_ERROR_INIT;
    return 0;
  }
  if (mem || !file) {
    g_error = BASS_ERROR_FILEOPEN;
    return 0;
  }
  char *path = (flags & BASS_UNICODE) ? utf16_to_utf8((const uint16_t *)file) : strdup((const char *)file);
  decoder dec;
  int ok = dec_open(&dec, path);
  if (!ok) LOG("Can't open music file: %s", path);
  free(path);
  if (!ok) {
    g_error = BASS_ERROR_FILEOPEN;
    return 0;
  }
  pthread_mutex_lock(&g_lock);
  int idx = -1;
  for (int i = 0; i < MAX_STREAMS; i++)
    if (g_streams[i].state == ST_FREE) { idx = i; break; }
  if (idx < 0) {
    pthread_mutex_unlock(&g_lock);
    dec_close(&dec);
    g_error = BASS_ERROR_MEM;
    return 0;
  }
  stream *s = &g_streams[idx];
  uint32_t gen = s->gen;
  memset(s, 0, sizeof(*s));
  s->gen = gen;
  s->dec = dec;
  s->flags = flags;
  s->volume = 1.0f;
  s->state = ST_STOPPED;
  DWORD h = make_handle(idx);
  pthread_mutex_unlock(&g_lock);
  g_error = BASS_OK;
  return h;
}

API BOOL BASS_StreamFree(DWORD handle) {
  pthread_mutex_lock(&g_lock);
  stream *s = get_stream(handle);
  if (s) s->req_free = 1;
  pthread_mutex_unlock(&g_lock);
  g_error = s ? BASS_OK : BASS_ERROR_HANDLE;
  return s != NULL;
}

API BOOL BASS_ChannelPlay(DWORD handle, BOOL restart) {
  pthread_mutex_lock(&g_lock);
  stream *s = get_stream(handle);
  if (s) {
    if (restart || s->state == ST_STOPPED) s->req_restart = 1;
    s->state = ST_PLAYING;
  }
  pthread_mutex_unlock(&g_lock);
  g_error = s ? BASS_OK : BASS_ERROR_HANDLE;
  return s != NULL;
}

API BOOL BASS_ChannelStop(DWORD handle) {
  pthread_mutex_lock(&g_lock);
  stream *s = get_stream(handle);
  if (s) {
    s->state = ST_STOPPED;
    if (s->flags & BASS_STREAM_AUTOFREE) s->req_free = 1;
  }
  pthread_mutex_unlock(&g_lock);
  g_error = s ? BASS_OK : BASS_ERROR_HANDLE;
  return s != NULL;
}

API BOOL BASS_ChannelPause(DWORD handle) {
  pthread_mutex_lock(&g_lock);
  stream *s = get_stream(handle);
  if (s && s->state == ST_PLAYING) s->state = ST_PAUSED;
  pthread_mutex_unlock(&g_lock);
  g_error = s ? BASS_OK : BASS_ERROR_HANDLE;
  return s != NULL;
}

API DWORD BASS_ChannelIsActive(DWORD handle) {
  DWORD r = BASS_ACTIVE_STOPPED;
  pthread_mutex_lock(&g_lock);
  stream *s = get_stream(handle);
  if (s) r = s->state == ST_PLAYING ? BASS_ACTIVE_PLAYING : s->state == ST_PAUSED ? BASS_ACTIVE_PAUSED : BASS_ACTIVE_STOPPED;
  pthread_mutex_unlock(&g_lock);
  return r;
}

API BOOL BASS_ChannelSetAttribute(DWORD handle, DWORD attrib, float value) {
  pthread_mutex_lock(&g_lock);
  stream *s = get_stream(handle);
  if (s && attrib == BASS_ATTRIB_VOL) {
    s->sliding = 0;
    s->volume = value < 0 ? 0 : value;
  }
  pthread_mutex_unlock(&g_lock);
  g_error = s ? BASS_OK : BASS_ERROR_HANDLE;
  return s != NULL;
}

API BOOL BASS_ChannelGetAttribute(DWORD handle, DWORD attrib, float *value) {
  pthread_mutex_lock(&g_lock);
  stream *s = get_stream(handle);
  if (s && attrib == BASS_ATTRIB_VOL) *value = current_volume(s, now_ms());
  pthread_mutex_unlock(&g_lock);
  g_error = s ? BASS_OK : BASS_ERROR_HANDLE;
  return s != NULL;
}

API BOOL BASS_ChannelSlideAttribute(DWORD handle, DWORD attrib, float value, DWORD time) {
  pthread_mutex_lock(&g_lock);
  stream *s = get_stream(handle);
  if (s && attrib == BASS_ATTRIB_VOL) {
    uint64_t t = now_ms();
    s->slide_from = current_volume(s, t);
    s->slide_to = value < 0 ? 0 : value;
    s->slide_start_ms = t;
    s->slide_time_ms = time;
    s->sliding = 1;
  }
  pthread_mutex_unlock(&g_lock);
  g_error = s ? BASS_OK : BASS_ERROR_HANDLE;
  return s != NULL;
}
