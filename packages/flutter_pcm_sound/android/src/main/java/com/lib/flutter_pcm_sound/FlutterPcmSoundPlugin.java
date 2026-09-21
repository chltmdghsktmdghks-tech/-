package com.lib.flutter_pcm_sound;

import android.os.Build;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.AudioAttributes;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import androidx.annotation.NonNull;

import java.util.Map;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.io.StringWriter;
import java.io.PrintWriter;
import java.nio.ByteBuffer;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * FlutterPcmSoundPlugin implements a "one pedal" PCM sound playback mechanism.
 * Playback starts automatically when samples are fed and stops when no more samples are available.
 */
public class FlutterPcmSoundPlugin implements
    FlutterPlugin,
    MethodChannel.MethodCallHandler
{
    private static final String CHANNEL_NAME = "flutter_pcm_sound/methods";
    private static final int MAX_FRAMES_PER_BUFFER = 200;

    private MethodChannel mMethodChannel;
    private Handler mainThreadHandler = new Handler(Looper.getMainLooper());
    private Thread playbackThread;
    private volatile boolean mShouldCleanup = false;

    private AudioTrack mAudioTrack;
    private int mNumChannels;
    private int mMinBufferSize;
    private boolean mDidSetup = false;

    private long mFeedThreshold = 8000;
    private long mTotalFeeds = 0;
    private long mLastLowBufferFeed = 0;
    private long mLastZeroFeed = 0;

    // 음악 낙서장 수정: "지금 큐에 몇 바이트 남았나"를 재생 스레드가 매 버퍼마다
    // `mSamples` 전체를 훑어(`for (ByteBuffer b : mSamples) totalBytes += ...`)
    // 다시 세고 있었다 — 큐가 길어지면(피드가 몰릴 때) 이 계산 자체가
    // `synchronized (mSamples)` 를 오래 붙들었고, 그동안 Dart 쪽 "feed" 호출이
    // 같은 락을 기다리며 실기기에서 최대 438ms까지 막혔다(`Long monitor
    // contention` 경고로 확인 — 재생 중 "노이즈"로 들리던 것의 원인). 큐 총
    // 바이트 수를 넣고 뺄 때마다 갱신되는 값으로 따로 들고 있으면 이 구간이
    // 큐 길이와 무관하게 항상 O(1)이 된다.
    private long mQueuedBytes = 0;

    // Thread-safe queue for storing audio samples
    private final LinkedBlockingQueue<ByteBuffer> mSamples = new LinkedBlockingQueue<>();

    // Log level enum (kept for potential future use)
    private enum LogLevel {
        NONE,
        ERROR,
        STANDARD,
        VERBOSE
    }

    private LogLevel mLogLevel = LogLevel.VERBOSE;

    // 음악 낙서장 수정: 장치의 기본 버스트 크기를 알아내려면 Context 가 필요하다
    private android.content.Context mContext;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        mContext = binding.getApplicationContext();
        BinaryMessenger messenger = binding.getBinaryMessenger();
        mMethodChannel = new MethodChannel(messenger, CHANNEL_NAME);
        mMethodChannel.setMethodCallHandler(this);
    }

    /**
     * 음악 낙서장 수정: 이 장치가 한 번에 처리하는 프레임 수(버스트).
     * 저지연 경로를 타려면 버퍼가 이 값의 작은 배수여야 한다. 못 읽으면 256.
     */
    private int nativeBurstFrames() {
        try {
            AudioManager am = (AudioManager) mContext.getSystemService(android.content.Context.AUDIO_SERVICE);
            String s = am.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER);
            if (s != null) {
                int v = Integer.parseInt(s);
                if (v > 0) return v;
            }
        } catch (Exception e) {
            // 못 읽으면 기본값으로
        }
        return 256;
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        mMethodChannel.setMethodCallHandler(null);
        cleanup();
    }

    @Override
    @SuppressWarnings("deprecation") // Needed for compatibility with Android < 23
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "setLogLevel": {
                    result.success(true);
                    break;
                }
                case "setup": {
                    int sampleRate = call.argument("sample_rate");
                    mNumChannels = call.argument("num_channels");

                    // Cleanup existing resources if any
                    if (mAudioTrack != null) {
                        cleanup();
                    }

                    int channelConfig = (mNumChannels == 2) ?
                        AudioFormat.CHANNEL_OUT_STEREO :
                        AudioFormat.CHANNEL_OUT_MONO;

                    mMinBufferSize = AudioTrack.getMinBufferSize(
                        sampleRate, channelConfig, AudioFormat.ENCODING_PCM_16BIT);

                    if (mMinBufferSize == AudioTrack.ERROR || mMinBufferSize == AudioTrack.ERROR_BAD_VALUE) {
                        result.error("AudioTrackError", "Invalid buffer size.", null);
                        return;
                    }

                    if (Build.VERSION.SDK_INT >= 23) { // Android 6 (Marshmallow) and above
                        // ── 음악 낙서장 수정: 저지연 경로 요청 ──
                        // 원본은 performance mode 를 지정하지 않고 버퍼를 getMinBufferSize() 그대로 썼다.
                        // 그 값은 **일반(딥 버퍼) 경로의 최소값**이라 아주 크다.
                        // A17 실측: 6156프레임 = 138ms. 건반을 누르면 그만큼 늦게 소리가 난다.
                        //
                        // 저지연 경로(fast mixer)를 타려면 두 가지가 맞아야 한다:
                        //   ① 표본화 주파수가 장치 기본값과 같을 것 (보통 48000)
                        //   ② 버퍼가 장치 버스트(PROPERTY_OUTPUT_FRAMES_PER_BUFFER)의 작은 배수일 것
                        // 둘 다 맞으면 플래그에 FAST 가 붙는다. 안 맞으면 조용히 무시되고 예전처럼 돈다.
                        int bufBytes = mMinBufferSize;
                        if (Build.VERSION.SDK_INT >= 26) {
                            int burst = nativeBurstFrames();
                            int frameBytes = 2 * mNumChannels; // 16bit
                            // 버스트 8개.
                            // 4개(1024프레임=21ms)에서 8개로 올렸다. 총 지연은 안 늘어난다 —
                            // `ahead`(우리가 앞질러 두는 총량)는 큐 + AudioTrack 을 합친 값이라,
                            // 장치 버퍼가 커지면 같은 총량 중 더 많은 몫이 장치 안에 있을 뿐이다.
                            // 대신 쓰기 스레드가 늦게 깨도 버틸 여유가 두 배가 된다.
                            // (예전 주석: 버스트 4개.
                            // 2개(=512프레임, 21ms)까지 줄여 봤더니 저지연 경로는 잡혔지만
                            // 언더런이 초당 1000개 넘게 계속 늘었다. 이유는 아래 구조 때문이다:
                            //   AudioTrack 이 비면 → 쓰기 스레드가 큐에서 꺼내 채운다 →
                            //   그 큐는 Dart 쪽 feed 콜백이 채운다 → **그 콜백은 UI 스레드를 거친다.**
                            // 즉 화면이 한 번 버벅이면 그대로 소리가 끊긴다.
                            // 버퍼가 이 지연을 흡수해 줘야 하고, 실측상 4개가 하한이었다.
                            // 더 줄이려면 엔진을 별도 아이솔레이트로 옮겨야 한다 (다음 작업).
                            //  더 줄이려면 엔진을 별도 아이솔레이트로 옮겨야 한다 — 그건 끝냈다.)
                            int want = burst * 8 * frameBytes;
                            if (want > 0 && want < bufBytes) bufBytes = want;
                        }
                        AudioTrack.Builder b = new AudioTrack.Builder()
                            .setAudioAttributes(new AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_MEDIA)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                    .build())
                            .setAudioFormat(new AudioFormat.Builder()
                                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                    .setSampleRate(sampleRate)
                                    .setChannelMask(channelConfig)
                                    .build())
                            .setBufferSizeInBytes(bufBytes)
                            .setTransferMode(AudioTrack.MODE_STREAM);
                        if (Build.VERSION.SDK_INT >= 26) {
                            b.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY);
                        }
                        try {
                            mAudioTrack = b.build();
                        } catch (Exception lowLatencyFailed) {
                            // 저지연 버퍼가 거부되면 원래 방식으로 되돌린다
                            mAudioTrack = new AudioTrack.Builder()
                                .setAudioAttributes(new AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_MEDIA)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                        .build())
                                .setAudioFormat(new AudioFormat.Builder()
                                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                        .setSampleRate(sampleRate)
                                        .setChannelMask(channelConfig)
                                        .build())
                                .setBufferSizeInBytes(mMinBufferSize)
                                .setTransferMode(AudioTrack.MODE_STREAM)
                                .build();
                        }
                    } else {
                        mAudioTrack = new AudioTrack(
                            AudioManager.STREAM_MUSIC,
                            sampleRate,
                            channelConfig,
                            AudioFormat.ENCODING_PCM_16BIT,
                            mMinBufferSize,
                            AudioTrack.MODE_STREAM);
                    }

                    if (mAudioTrack.getState() != AudioTrack.STATE_INITIALIZED) {
                        result.error("AudioTrackError", "AudioTrack initialization failed.", null);
                        mAudioTrack.release();
                        mAudioTrack = null;
                        return;
                    }

                    // reset
                    mSamples.clear();
                    synchronized (mSamples) {
                        mQueuedBytes = 0;
                    }
                    mShouldCleanup = false;

                    // start playback thread
                    playbackThread = new Thread(this::playbackThreadLoop, "PCMPlaybackThread");
                    playbackThread.setPriority(Thread.MAX_PRIORITY);
                    playbackThread.start();

                    mDidSetup = true;

                    result.success(true);
                    break;
                }
                case "feed": {

                    // check setup (to match iOS behavior)
                    if (mDidSetup == false) {
                        result.error("Setup", "must call setup first", null);
                        return;
                    }

                    byte[] buffer = call.argument("buffer");

                    // Split for better performance
                    List<ByteBuffer> chunks = split(buffer, MAX_FRAMES_PER_BUFFER);

                    // Push samples
                    synchronized (mSamples) {
                        for (ByteBuffer chunk : chunks) {
                            mSamples.add(chunk);
                            mQueuedBytes += chunk.remaining();
                        }
                        mTotalFeeds += 1;
                    }

                    result.success(true);
                    break;
                }
                // ── 음악 낙서장 추가 ──
                // 원본에는 '지금 큐에 얼마나 남았나'를 물어보는 방법이 없고,
                // 콜백으로 알려 주기만 한다. 그런데 그 콜백은 **루트(UI) 아이솔레이트로** 간다.
                // 오디오를 백그라운드 아이솔레이트로 옮기면 그 콜백을 받을 수 없으므로,
                // 직접 물어볼 수 있어야 한다. 이게 있어야 시계 드리프트도 바로잡을 수 있다.
                case "remainingFrames": {
                    long totalBytes;
                    synchronized (mSamples) {
                        totalBytes = mQueuedBytes;
                    }
                    result.success(totalBytes / (2 * mNumChannels));
                    break;
                }
                case "setFeedThreshold": {
                    long feedThreshold = ((Number) call.argument("feed_threshold")).longValue();

                    synchronized (mSamples) {
                        mFeedThreshold = feedThreshold;
                    }

                    result.success(true);
                    break;
                }
                case "release": {
                    cleanup();
                    result.success(true);
                    break;
                }
                default:
                    result.notImplemented();
                    break;
            }


        } catch (Exception e) {
            StringWriter sw = new StringWriter();
            PrintWriter pw = new PrintWriter(sw);
            e.printStackTrace(pw);
            String stackTrace = sw.toString();
            result.error("androidException", e.toString(), stackTrace);
            return;
        }
    }

    /**
     * Cleans up resources by stopping the playback thread and releasing AudioTrack.
     */
    private void cleanup() {
        // stop playback thread
        if (playbackThread != null) {
            mShouldCleanup = true;
            playbackThread.interrupt();
            try {
                playbackThread.join();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            playbackThread = null;
            mDidSetup = false;
        }
    }

    /**
     * Invokes the 'OnFeedSamples' callback with the number of remaining frames.
     */
    private void invokeFeedCallback(long remainingFrames) {
        Map<String, Object> response = new HashMap<>();
        response.put("remaining_frames", remainingFrames);
        mMethodChannel.invokeMethod("OnFeedSamples", response);
    }

    /**
     * The main loop of the playback thread.
     */
    private void playbackThreadLoop() {
        // 음악 낙서장 수정: AUDIO(-16) → URGENT_AUDIO(-19).
        // 이 스레드가 늦게 깨면 큐에 데이터가 있어도 AudioTrack 이 빈다.
        // A17 실측: 큐 최소 잔량 1898프레임(안 비었음)인데 dumpsys 언더런이 초당 7.5회 —
        // 즉 남은 원인은 Dart 쪽이 아니라 **이 쓰기 스레드의 스케줄링**이다.
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO);

        mAudioTrack.play();

        while (!mShouldCleanup) {
            ByteBuffer data = null;
            try {
                // blocks indefinitely until new data
                data = mSamples.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                continue;
            }

            // write — 다 쓰기 전에 크기를 적어 둔다(쓰고 나면 remaining()이 0이 된다)
            int consumedBytes = data.remaining();
            mAudioTrack.write(data, consumedBytes, AudioTrack.WRITE_BLOCKING);

            long remainingFrames;
            long totalFeeds;
            long feedThreshold;

            // grab shared data — 큐를 훑지 않고 미리 세어 둔 값만 갱신한다(O(1))
            synchronized (mSamples) {
                mQueuedBytes -= consumedBytes;
                remainingFrames = mQueuedBytes / (2 * mNumChannels);
                totalFeeds = mTotalFeeds;
                feedThreshold = mFeedThreshold;
            }

            // check for events
            boolean isLowBufferEvent = (remainingFrames <= feedThreshold) && (mLastLowBufferFeed != totalFeeds);
            boolean isZeroCrossingEvent = (remainingFrames == 0) && (mLastZeroFeed != totalFeeds);

            // send events
            if (isLowBufferEvent || isZeroCrossingEvent) {
                if (isLowBufferEvent) {mLastLowBufferFeed = totalFeeds;}
                if (isZeroCrossingEvent) {mLastZeroFeed = totalFeeds;}
                mainThreadHandler.post(() -> invokeFeedCallback(remainingFrames));
            }
        }

        mAudioTrack.stop();
        mAudioTrack.flush();
        mAudioTrack.release();
        mAudioTrack = null;
    }


    private List<ByteBuffer> split(byte[] buffer, int maxSize) {
        List<ByteBuffer> chunks = new ArrayList<>();
        int offset = 0;
        while (offset < buffer.length) {
            int length = Math.min(buffer.length - offset, maxSize);
            ByteBuffer b = ByteBuffer.wrap(buffer, offset, length);
            chunks.add(b);
            offset += length;
        }
        return chunks;
    }
}
