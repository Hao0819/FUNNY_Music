package com.example.music_player

import android.database.Cursor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Adds a broader audio scan than `on_audio_query` performs.
 *
 * That plugin queries `MediaStore.Audio.Media.EXTERNAL_CONTENT_URI`, which
 * only covers the primary volume and only rows MediaStore actually classified
 * as audio. Files that landed in the generic "files" collection — common for
 * anything a downloader or file manager dropped into Download/ with an odd
 * mime type — are invisible to it. This queries the files collection across
 * every volume and keeps anything that looks like audio.
 */
class MainActivity : AudioServiceActivity() {

    private companion object {
        const val CHANNEL = "music_player/media_store"

        val AUDIO_EXTENSIONS = setOf(
            "mp3", "m4a", "m4b", "aac", "wav", "flac", "ogg", "oga", "opus",
            "wma", "aiff", "aif", "alac", "mka", "mid", "amr", "3gp",
        )
    }

    private val queryExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var ytdlpBridge: YtdlpBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ytdlpBridge = YtdlpBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                // Scanning a real library walks thousands of MediaStore rows.
                // Method-channel handlers run on the main thread, so doing that
                // work here directly freezes the UI before it can paint a
                // frame. Query on a worker and hand the result back on main.
                "queryAudioFiles" -> queryExecutor.execute {
                    try {
                        val rows = queryAudioFiles()
                        mainHandler.post { result.success(rows) }
                    } catch (error: Exception) {
                        // Never let a scan failure take down the library — the
                        // plugin's own results still stand on their own.
                        mainHandler.post { result.error("QUERY_FAILED", error.message, null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        ytdlpBridge?.dispose()
        queryExecutor.shutdown()
        super.onDestroy()
    }

    private fun queryAudioFiles(): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()
        val seenPaths = mutableSetOf<String>()

        for (volume in audioVolumeNames()) {
            val uri = try {
                MediaStore.Files.getContentUri(volume)
            } catch (error: Exception) {
                continue
            }

            val projection = arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DATA,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.TITLE,
                MediaStore.Files.FileColumns.MIME_TYPE,
                MediaStore.Files.FileColumns.DATE_ADDED,
                MediaStore.Audio.AudioColumns.DURATION,
                MediaStore.Audio.AudioColumns.ARTIST,
                MediaStore.Audio.AudioColumns.ALBUM,
            )

            val selection =
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ${MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO}" +
                    " OR ${MediaStore.Files.FileColumns.MIME_TYPE} LIKE 'audio/%'"

            var cursor: Cursor? = null
            try {
                cursor = contentResolver.query(uri, projection, selection, null, null)
            } catch (error: Exception) {
                // A volume that rejects the projection shouldn't stop the rest.
                continue
            }

            cursor?.use {
                val idColumn = it.getColumnIndex(MediaStore.Files.FileColumns._ID)
                val dataColumn = it.getColumnIndex(MediaStore.Files.FileColumns.DATA)
                val displayNameColumn = it.getColumnIndex(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val titleColumn = it.getColumnIndex(MediaStore.Files.FileColumns.TITLE)
                val mimeColumn = it.getColumnIndex(MediaStore.Files.FileColumns.MIME_TYPE)
                val dateAddedColumn = it.getColumnIndex(MediaStore.Files.FileColumns.DATE_ADDED)
                val durationColumn = it.getColumnIndex(MediaStore.Audio.AudioColumns.DURATION)
                val artistColumn = it.getColumnIndex(MediaStore.Audio.AudioColumns.ARTIST)
                val albumColumn = it.getColumnIndex(MediaStore.Audio.AudioColumns.ALBUM)

                while (it.moveToNext()) {
                    val path = if (dataColumn >= 0) it.getString(dataColumn) else null
                    if (path.isNullOrBlank() || !seenPaths.add(path)) continue

                    val mime = if (mimeColumn >= 0) it.getString(mimeColumn) else null
                    if (!looksLikeAudio(path, mime)) continue

                    rows.add(
                        mapOf(
                            "id" to if (idColumn >= 0) it.getLong(idColumn) else 0L,
                            "path" to path,
                            "title" to (
                                it.stringOrNull(titleColumn) ?: it.stringOrNull(displayNameColumn)
                                ),
                            "artist" to it.stringOrNull(artistColumn),
                            "album" to it.stringOrNull(albumColumn),
                            "duration" to if (durationColumn >= 0) it.getLong(durationColumn) else 0L,
                            "dateAdded" to if (dateAddedColumn >= 0) it.getLong(dateAddedColumn) else 0L,
                        )
                    )
                }
            }
        }

        return rows
    }

    private fun audioVolumeNames(): Set<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.getExternalVolumeNames(this)
        } else {
            setOf("external")
        }
    }

    private fun looksLikeAudio(path: String, mimeType: String?): Boolean {
        if (mimeType != null && mimeType.startsWith("audio/")) return true
        val extension = path.substringAfterLast('.', "").lowercase()
        return extension in AUDIO_EXTENSIONS
    }

    private fun Cursor.stringOrNull(column: Int): String? {
        if (column < 0 || isNull(column)) return null
        return getString(column)
    }
}
