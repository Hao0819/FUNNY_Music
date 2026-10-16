package com.example.music_player

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicLong

/**
 * Bridges Flutter to the embedded yt-dlp.
 *
 * `youtubedl-android` bundles a Python 3 runtime and yt-dlp inside the APK and
 * runs them on-device; FFmpeg alongside it turns the downloaded stream into a
 * tagged audio file. Everything here is blocking native work, so no call
 * touches the main thread beyond posting results back to it.
 *
 * Finished files are published into MediaStore rather than left in app
 * storage, so the library scan in `MainActivity` picks them up like any other
 * track on the device.
 */
class YtdlpBridge(private val context: Context, messenger: BinaryMessenger) {

    private companion object {
        const val TAG = "YtdlpBridge"

        const val METHOD_CHANNEL = "music_player/ytdlp"
        const val EVENT_CHANNEL = "music_player/ytdlp/events"

        /** Sub-directory of the shared Music/ collection downloads land in. */
        const val PUBLIC_SUBDIR = "MusicPlayer"

        /** How often the thread waiting on a download looks in on it. */
        const val POLL_MS = 2_000L

        /**
         * How long a download may produce nothing at all — no output line, no
         * growth in the file it is writing — before it counts as wedged
         * rather than slow.
         *
         * Generous on purpose: extracting audio from a long recording can run
         * for a while without printing anything, and cutting that short would
         * throw away a download that was about to finish.
         */
        const val IDLE_LIMIT_MS = 180_000L

        /** Extensions yt-dlp gives a file it has not finished writing. */
        val PARTIAL_EXTENSIONS = setOf("part", "ytdl", "tmp")
    }

    // init and each download block for a long time, so they can't share a
    // single-threaded executor or one download would stall the next request.
    private val worker = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Downloads yt-dlp is still running, so one can be told apart from a cancel. */
    private val activeDownloads = ConcurrentHashMap<String, Boolean>()

    /**
     * The yt-dlp call behind each running download, so a cancel can interrupt
     * the thread reading its output and not just kill the process.
     */
    private val runners = ConcurrentHashMap<String, Future<*>>()

    @Volatile
    private var initialized = false

    @Volatile
    private var initError: String? = null

    private var eventSink: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> worker.execute { ensureInitialized(result) }
                "version" -> worker.execute { version(result) }
                "updateYtdlp" -> worker.execute { updateYtdlp(result) }
                "fetchInfo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    worker.execute { fetchInfo(url, result) }
                }
                "search" -> {
                    val query = call.argument<String>("query").orEmpty()
                    val limit = call.argument<Int>("limit") ?: 20
                    worker.execute { search(query, limit, result) }
                }
                "startDownload" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val format = call.argument<String>("format") ?: "mp3"
                    startDownload(url, format, result)
                }
                "cancel" -> {
                    val id = call.argument<String>("id").orEmpty()
                    cancel(id, result)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    fun dispose() {
        // Processes first: shutting the pool down interrupts the threads
        // waiting on them, but the Python process each download started is a
        // process of its own and would otherwise go on running — and keep the
        // app alive with it — after the window it was started from is gone.
        for (id in activeDownloads.keys) {
            activeDownloads.remove(id)
            destroyProcess(id)
        }
        runners.clear()
        worker.shutdownNow()
    }

    // --- lifecycle -------------------------------------------------------

    /**
     * Unpacks the Python runtime and FFmpeg on first call. That costs several
     * seconds and rewrites app storage, so it runs once and the result is
     * cached — the failure too, because a failed unpack fails the same way
     * every time and retrying just burns another few seconds.
     *
     * Catches [Throwable] rather than [Exception], as does the rest of this
     * class: a payload that won't unpack surfaces as an `Error`
     * (`ExceptionInInitializerError`, `UnsatisfiedLinkError`), and letting one
     * escape a pool thread kills the process instead of failing the one call.
     */
    private fun ensureInitialized(result: MethodChannel.Result?) {
        if (initialized) {
            reply(result) { it.success(true) }
            return
        }
        initError?.let { cached ->
            reply(result) { it.error("INIT_FAILED", cached, null) }
            return
        }

        try {
            YoutubeDL.getInstance().init(context)
            FFmpeg.getInstance().init(context)
            initialized = true
            reply(result) { it.success(true) }
        } catch (error: Throwable) {
            initError = error.message ?: error.toString()
            reply(result) { it.error("INIT_FAILED", initError, null) }
        }
    }

    private fun version(result: MethodChannel.Result) {
        if (!initializedOrFail(result)) return
        try {
            val version = YoutubeDL.getInstance().version(context)
            reply(result) { it.success(version) }
        } catch (error: Throwable) {
            reply(result) { it.error("VERSION_FAILED", error.message, null) }
        }
    }

    /**
     * Pulls a fresh yt-dlp. YouTube's player JavaScript changes often enough
     * that extraction breaks between app releases, so this is the escape hatch
     * that doesn't need a new APK.
     */
    private fun updateYtdlp(result: MethodChannel.Result) {
        if (!initializedOrFail(result)) return
        try {
            val status = YoutubeDL.getInstance().updateYoutubeDL(context)
            reply(result) { it.success(status?.toString() ?: "UNKNOWN") }
        } catch (error: Throwable) {
            reply(result) { it.error("UPDATE_FAILED", error.message, null) }
        }
    }

    // --- metadata --------------------------------------------------------

    private fun fetchInfo(url: String, result: MethodChannel.Result) {
        if (url.isBlank()) {
            reply(result) { it.error("BAD_URL", "No URL given", null) }
            return
        }
        if (!initializedOrFail(result)) return

        try {
            val info = YoutubeDL.getInstance().getInfo(YoutubeDLRequest(url))
            val payload = mapOf(
                "id" to info.id,
                "title" to info.title,
                "uploader" to info.uploader,
                "duration" to info.duration.toLong(),
                "thumbnail" to info.thumbnail,
            )
            reply(result) { it.success(payload) }
        } catch (error: Throwable) {
            reply(result) { it.error("INFO_FAILED", error.message, null) }
        }
    }

    /**
     * Searches with yt-dlp's own `ytsearch` prefix rather than the YouTube Data
     * API — no API key to embed, no daily quota, and nothing beyond what the
     * downloader already does.
     *
     * `--flat-playlist` skips resolving each hit's stream formats, which is the
     * difference between a couple of seconds and most of a minute.
     */
    private fun search(query: String, limit: Int, result: MethodChannel.Result) {
        if (query.isBlank()) {
            reply(result) { it.error("BAD_QUERY", "No search terms given", null) }
            return
        }
        if (!initializedOrFail(result)) return

        try {
            val request = YoutubeDLRequest("ytsearch$limit:$query").apply {
                addOption("--flat-playlist")
                addOption("--dump-json")
                addOption("--no-warnings")
                // One unavailable hit shouldn't lose the whole result set.
                addOption("--ignore-errors")
            }

            val output = YoutubeDL.getInstance().execute(request).out
            val rows = parseSearchOutput(output)
            Log.i(TAG, "search(\"$query\") returned ${rows.size} result(s)")
            reply(result) { it.success(rows) }
        } catch (error: Throwable) {
            Log.w(TAG, "search(\"$query\") failed", error)
            reply(result) { it.error("SEARCH_FAILED", error.message ?: error.toString(), null) }
        }
    }

    /**
     * `--dump-json` writes one JSON object per line. Field names drift between
     * yt-dlp releases, so every lookup here takes alternatives and a missing
     * one costs that field rather than the row.
     */
    private fun parseSearchOutput(output: String): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()

        for (line in output.lineSequence()) {
            val trimmed = line.trim()
            if (!trimmed.startsWith("{")) continue

            val json = try {
                JSONObject(trimmed)
            } catch (error: Throwable) {
                continue
            }

            val id = json.optString("id").takeIf { it.isNotBlank() } ?: continue
            rows.add(
                mapOf(
                    "id" to id,
                    "title" to json.stringOrNull("title").orEmpty(),
                    "uploader" to (
                        json.stringOrNull("channel")
                            ?: json.stringOrNull("uploader")
                            ?: json.stringOrNull("uploader_id")
                            ?: ""
                        ),
                    "duration" to json.optDouble("duration", 0.0).toLong(),
                    "thumbnail" to (json.stringOrNull("thumbnail") ?: json.firstThumbnail()),
                    // A flat search entry's own url is already watchable; the
                    // fallback covers releases that only report the id.
                    "url" to (
                        json.stringOrNull("url")
                            ?: json.stringOrNull("webpage_url")
                            ?: "https://www.youtube.com/watch?v=$id"
                        ),
                )
            )
        }

        if (rows.isEmpty() && output.isNotBlank()) {
            // Makes a field-name change diagnosable without another build.
            Log.w(TAG, "search parsed 0 rows from: ${output.take(400)}")
        }
        return rows
    }

    private fun JSONObject.stringOrNull(key: String): String? {
        if (!has(key) || isNull(key)) return null
        return optString(key).takeIf { it.isNotBlank() && it != "null" }
    }

    /** Thumbnails come as an array ordered worst to best; the last is largest. */
    private fun JSONObject.firstThumbnail(): String? {
        val thumbnails = optJSONArray("thumbnails") ?: return null
        for (index in thumbnails.length() - 1 downTo 0) {
            val url = thumbnails.optJSONObject(index)?.stringOrNull("url")
            if (url != null) return url
        }
        return null
    }

    // --- downloading -----------------------------------------------------

    /**
     * Returns a download id immediately; progress, completion and failure all
     * arrive on the event channel keyed by that id.
     */
    private fun startDownload(url: String, format: String, result: MethodChannel.Result) {
        if (url.isBlank()) {
            result.error("BAD_URL", "No URL given", null)
            return
        }

        val downloadId = UUID.randomUUID().toString()
        activeDownloads[downloadId] = true
        result.success(downloadId)

        worker.execute {
            Log.i(TAG, "download($downloadId) starting: $url")
            emit(downloadId, "progress", mapOf("progress" to 0.0, "eta" to 0L, "line" to "Starting…"))

            // Downloading can be the first thing the user does, so don't
            // assume yt-dlp has been unpacked yet.
            ensureInitialized(null)
            if (!initialized) {
                emit(downloadId, "error", mapOf("message" to (initError ?: "yt-dlp is not available")))
                activeDownloads.remove(downloadId)
                return@execute
            }

            // A private scratch directory per download makes "which file did
            // this produce" answerable without parsing yt-dlp's output.
            val scratch = File(context.cacheDir, "ytdlp/$downloadId").apply { mkdirs() }

            try {
                val request = YoutubeDLRequest(url).apply {
                    addOption("-f", "bestaudio/best")
                    addOption("-x")
                    addOption("--audio-format", format)
                    addOption("--audio-quality", "0")
                    addOption("--embed-metadata")
                    addOption("--no-playlist")
                    // Leaves the file's timestamp at download time, so the
                    // library's "recently added" sort puts it on top.
                    addOption("--no-mtime")
                    addOption("-o", File(scratch, "%(title)s.%(ext)s").absolutePath)
                }

                Log.i(TAG, "download($downloadId) invoking yt-dlp")
                val lastOutput = AtomicLong(System.currentTimeMillis())

                // Run on a thread of its own and waited on rather than called
                // straight: `execute` reads yt-dlp's output until end of
                // stream, and the FFmpeg child spawned for the audio
                // extraction can hold that stream open after the file is
                // finished and written. The call then never returns — the
                // download was done, the row kept its progress bar, and
                // nothing short of force-stopping the app got rid of it.
                val runner = worker.submit {
                    YoutubeDL.getInstance().execute(request, downloadId) { progress, eta, line ->
                        lastOutput.set(System.currentTimeMillis())
                        Log.v(TAG, "download($downloadId) $progress% $line")
                        emit(
                            downloadId,
                            "progress",
                            mapOf(
                                "progress" to progress.toDouble(),
                                "eta" to eta,
                                "line" to line,
                            ),
                        )
                    }
                }
                runners[downloadId] = runner

                val stalled = !awaitRunner(downloadId, runner, scratch, lastOutput)
                Log.i(TAG, "download($downloadId) yt-dlp done, stalled=$stalled")

                // A cancel that landed while we were waiting: the row has
                // already been told, and the half-written file goes with the
                // scratch directory.
                if (!activeDownloads.containsKey(downloadId)) {
                    emit(downloadId, "cancelled", emptyMap())
                    return@execute
                }

                val produced = producedFile(scratch, format, finishedOnly = stalled)
                if (produced == null) {
                    val message = if (stalled) {
                        "yt-dlp stopped responding before it finished"
                    } else {
                        "yt-dlp produced no file"
                    }
                    emit(downloadId, "error", mapOf("message" to message))
                    return@execute
                }

                val published = publishToMediaStore(produced, format)
                Log.i(TAG, "download($downloadId) published to $published")
                emit(
                    downloadId,
                    "done",
                    mapOf("path" to published, "title" to produced.nameWithoutExtension),
                )
            } catch (error: Throwable) {
                Log.w(TAG, "download($downloadId) ended with an exception", error)
                // A cancel tears the process down from under us; that surfaces
                // as an exception but isn't a failure worth reporting as one.
                if (activeDownloads.containsKey(downloadId)) {
                    emit(downloadId, "error", mapOf("message" to (error.message ?: error.toString())))
                } else {
                    emit(downloadId, "cancelled", emptyMap())
                }
            } finally {
                activeDownloads.remove(downloadId)
                runners.remove(downloadId)
                scratch.deleteRecursively()
            }
        }
    }

    /**
     * Waits for [runner], giving up if the download goes completely quiet for
     * [IDLE_LIMIT_MS] — no output line and no growth in the file it is
     * writing.
     *
     * Returns false when it gave up, which is not the same as a failure: the
     * read can wedge after a perfectly good file has been written, so the
     * caller decides what the scratch directory is worth.
     */
    private fun awaitRunner(
        id: String,
        runner: Future<*>,
        scratch: File,
        lastOutput: AtomicLong,
    ): Boolean {
        var lastSize = -1L

        while (true) {
            try {
                runner.get(POLL_MS, TimeUnit.MILLISECONDS)
                return true
            } catch (timeout: TimeoutException) {
                // Still going; fall through to the checks below.
            } catch (cancelled: CancellationException) {
                return true
            } catch (failed: ExecutionException) {
                // yt-dlp's own failure. Unwrapped so the caller's catch block
                // reports what went wrong rather than "ExecutionException".
                throw failed.cause ?: failed
            }

            // Cancelled from the UI. cancel() has already killed the process
            // and interrupted the read, and has told the row itself.
            if (!activeDownloads.containsKey(id)) return true

            val size = scratchFootprint(scratch)
            if (size != lastSize) {
                lastSize = size
                lastOutput.set(System.currentTimeMillis())
            }
            if (System.currentTimeMillis() - lastOutput.get() < IDLE_LIMIT_MS) continue

            Log.w(TAG, "download($id) silent for ${IDLE_LIMIT_MS / 1000}s; giving up on the read")
            destroyProcess(id)
            runner.cancel(true)
            return false
        }
    }

    /**
     * Total bytes in a download's scratch directory.
     *
     * Summed rather than taken from the largest file: the transcode writes a
     * second, smaller file beside the stream it is reading, so watching the
     * largest one alone would see nothing happening for as long as the
     * extraction took.
     */
    private fun scratchFootprint(scratch: File): Long =
        scratch.listFiles()?.sumOf { it.length() } ?: -1L

    /**
     * The file a download produced, or null when there isn't one.
     *
     * Extraction leaves the original stream next to the transcode on some
     * formats, so the largest file wins rather than assuming there is exactly
     * one. [finishedOnly] insists on the extension that was asked for as
     * well: a download that was given up on mid-flight leaves a part file
     * behind, and filing that into the library would make half a song look
     * like a whole one.
     */
    private fun producedFile(scratch: File, format: String, finishedOnly: Boolean): File? {
        val files = scratch.listFiles()?.filter { it.isFile && it.length() > 0 } ?: return null
        val candidates = if (finishedOnly) {
            files.filter { it.extension.equals(format, ignoreCase = true) }
        } else {
            files.filterNot { it.extension.lowercase() in PARTIAL_EXTENSIONS }
        }
        return candidates.maxByOrNull { it.length() }
    }

    /** Returns false rather than throwing when there is no process to kill. */
    private fun destroyProcess(id: String): Boolean {
        return try {
            YoutubeDL.getInstance().destroyProcessById(id)
        } catch (error: Throwable) {
            Log.w(TAG, "destroyProcessById($id) failed", error)
            false
        }
    }

    private fun cancel(id: String, result: MethodChannel.Result) {
        // Dropped first, so the running thread can tell a cancel apart from a
        // genuine failure when its process dies.
        activeDownloads.remove(id)

        // False whenever the cancel lands outside the window where yt-dlp
        // actually has a process under this id.
        val killed = destroyProcess(id)

        // Killing yt-dlp does not reliably unblock the thread reading its
        // output — the FFmpeg child it spawned can still be holding that
        // stream open — so the read is interrupted too. Without this a
        // cancelled download went on occupying a thread, and its Python
        // process went on being a reason the app never fully closed.
        runners.remove(id)?.cancel(true)

        // Emitted here rather than left to the worker's catch block. Killing
        // the process doesn't reliably unblock `execute` — it can still be
        // reading a post-processing child's output — and without an event the
        // row would keep its progress bar and Cancel button forever.
        Log.i(TAG, "cancel($id): process killed=$killed")
        emit(id, "cancelled", emptyMap())
        result.success(killed)
    }

    // --- publishing ------------------------------------------------------

    /**
     * Moves a finished download out of app storage into the shared Music
     * collection, returning the path the library scan will see.
     */
    private fun publishToMediaStore(file: File, format: String): String? {
        val mime = when (format) {
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            "opus" -> "audio/opus"
            "flac" -> "audio/flac"
            else -> "audio/*"
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // No MediaStore insert API before Android 10. The app's own
            // external directory needs no storage permission there and still
            // sits on external storage, so the media scanner will index it.
            val target = File(
                context.getExternalFilesDir(Environment.DIRECTORY_MUSIC),
                PUBLIC_SUBDIR,
            ).apply { mkdirs() }
            val destination = File(target, file.name)
            file.copyTo(destination, overwrite = true)
            MediaScannerConnection.scanFile(context, arrayOf(destination.absolutePath), arrayOf(mime), null)
            return destination.absolutePath
        }

        val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Audio.Media.TITLE, file.nameWithoutExtension)
            put(MediaStore.Audio.Media.MIME_TYPE, mime)
            put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_MUSIC + "/" + PUBLIC_SUBDIR)
            put(MediaStore.Audio.Media.IS_MUSIC, 1)
            // Hides the row from other apps until the bytes are actually there.
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }

        val resolver = context.contentResolver
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore rejected the new track")

        val output = resolver.openOutputStream(uri)
            ?: throw IllegalStateException("Could not open the new track for writing")
        output.use { sink -> file.inputStream().use { source -> source.copyTo(sink) } }

        values.clear()
        values.put(MediaStore.Audio.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)

        // The library scans by file path, so resolve the row back to one.
        resolver.query(uri, arrayOf(MediaStore.Audio.Media.DATA), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0)
        }
        return uri.toString()
    }

    // --- plumbing --------------------------------------------------------

    private fun initializedOrFail(result: MethodChannel.Result): Boolean {
        ensureInitialized(null)
        if (!initialized) {
            reply(result) { it.error("INIT_FAILED", initError ?: "yt-dlp is not available", null) }
            return false
        }
        return true
    }

    private fun emit(id: String, type: String, payload: Map<String, Any?>) {
        val event = HashMap<String, Any?>(payload).apply {
            put("id", id)
            put("type", type)
        }
        mainHandler.post { eventSink?.success(event) }
    }

    private fun reply(result: MethodChannel.Result?, block: (MethodChannel.Result) -> Unit) {
        if (result == null) return
        mainHandler.post { block(result) }
    }
}
