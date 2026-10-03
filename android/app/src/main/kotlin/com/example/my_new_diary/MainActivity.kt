package com.example.my_new_diary

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.Settings
import java.io.FileNotFoundException
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterFragmentActivity() {
    private val deviceSettingsChannel =
        "com.huajianwu.shiguangdiary.v2/device_settings"
    private val diarySyncSafChannel =
        "com.huajianwu.shiguangdiary.v2/diary_sync_saf"
    private val pickTreeRequestCode = 7314
    private var pendingTreeResult: Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceSettingsChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "androidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                "openNotificationSettings" -> result.success(openNotificationSettings())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            diarySyncSafChannel,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "pickTree" -> pickTree(result)
                    "isAvailable" -> result.success(isTreeAvailable(requiredTreeUri(call.argument("treeUri"))))
                    "listEntryFiles" -> result.success(listFiles(requiredTreeUri(call.argument("treeUri")), "entries"))
                    "readEntry" -> result.success(readFile(requiredTreeUri(call.argument("treeUri")), "entries", requiredName(call.argument("name"), true)))
                    "writeEntry" -> result.success(writeFileSafely(requiredTreeUri(call.argument("treeUri")), "entries", requiredName(call.argument("name"), true), requiredBytes(call.argument("bytes"))))
                    "readImage" -> result.success(readFile(requiredTreeUri(call.argument("treeUri")), "images", requiredName(call.argument("name"), false)))
                    "writeImage" -> result.success(writeFileSafely(requiredTreeUri(call.argument("treeUri")), "images", requiredName(call.argument("name"), false), requiredBytes(call.argument("bytes"))))
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("SAF_${error.javaClass.simpleName}", "Diary sync storage operation failed.", null)
            }
        }
    }

    private fun pickTree(result: Result) {
        if (pendingTreeResult != null) {
            result.error("PICK_IN_PROGRESS", "A directory picker is already open.", null)
            return
        }
        pendingTreeResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        startActivityForResult(intent, pickTreeRequestCode)
    }

    @Deprecated("Deprecated by Android; retained for the Flutter activity result bridge.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickTreeRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingTreeResult
        pendingTreeResult = null
        if (result == null) return
        val treeUri = data?.data
        if (resultCode != RESULT_OK || treeUri == null) {
            result.success(null)
            return
        }
        try {
            val grantedFlags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            val requiredFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            if (grantedFlags and requiredFlags != requiredFlags) {
                throw SecurityException("The provider did not grant read/write access.")
            }
            contentResolver.takePersistableUriPermission(treeUri, grantedFlags)
            if (!isTreeAvailable(treeUri)) {
                throw SecurityException("Persisted tree permission is unavailable.")
            }
            result.success(
                mapOf(
                    "treeUri" to treeUri.toString(),
                    "displayName" to treeDisplayName(treeUri),
                ),
            )
        } catch (error: Exception) {
            result.error("SAF_${error.javaClass.simpleName}", "Could not persist directory access.", null)
        }
    }

    private fun requiredTreeUri(value: String?): Uri {
        if (value == null) throw IllegalArgumentException("Missing treeUri.")
        val uri = Uri.parse(value)
        if (uri.scheme != "content" || !DocumentsContract.isTreeUri(uri)) {
            throw IllegalArgumentException("Expected an Android document tree URI.")
        }
        return uri
    }

    private fun requiredName(value: String?, requireJson: Boolean): String {
        return SafPathValidatorV2.requireSafeName(value, requireJson)
    }

    private fun requiredBytes(value: ByteArray?): ByteArray =
        value ?: throw IllegalArgumentException("Missing file bytes.")

    private fun hasPersistedReadWritePermission(treeUri: Uri): Boolean {
        return contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission && it.isWritePermission
        }
    }

    private fun isTreeAvailable(treeUri: Uri): Boolean {
        if (!hasPersistedReadWritePermission(treeUri)) return false
        return try {
            ensureSyncDirectory(treeUri, "entries")
            ensureSyncDirectory(treeUri, "images")
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun treeDisplayName(treeUri: Uri): String {
        val root = rootDocumentUri(treeUri)
        return queryDocument(root)?.displayName ?: "Android 共享文件夹"
    }

    private fun listFiles(treeUri: Uri, bucket: String): List<String> {
        requireAvailable(treeUri)
        val directory = ensureSyncDirectory(treeUri, bucket)
        return queryChildren(treeUri, directory.documentId)
            .filter { it.mimeType != DocumentsContract.Document.MIME_TYPE_DIR }
            .map { it.displayName }
            .sorted()
    }

    private fun readFile(treeUri: Uri, bucket: String, name: String): ByteArray? {
        requireAvailable(treeUri)
        val directory = ensureSyncDirectory(treeUri, bucket)
        val file = findChild(treeUri, directory.documentId, name) ?: return null
        return contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
            ?: throw FileNotFoundException(name)
    }

    private fun writeFileSafely(
        treeUri: Uri,
        bucket: String,
        name: String,
        bytes: ByteArray,
    ): Boolean {
        requireAvailable(treeUri)
        val directory = ensureSyncDirectory(treeUri, bucket)
        val existing = findChild(treeUri, directory.documentId, name)
        if (existing != null) {
            val current = contentResolver.openInputStream(existing.uri)?.use { it.readBytes() }
            if (current != null && current.contentEquals(bytes)) return false
        }

        val temporaryName = "$name.tmp"
        val backupName = "$name.replace-old.tmp"
        findChild(treeUri, directory.documentId, temporaryName)?.let { deleteDocument(it.uri) }
        var backup = findChild(treeUri, directory.documentId, backupName)
        if (existing == null && backup != null) {
            DocumentsContract.renameDocument(contentResolver, backup.uri, name)
            backup = null
        }
        val currentTarget = findChild(treeUri, directory.documentId, name)
        val temporaryUri = DocumentsContract.createDocument(
            contentResolver,
            directory.uri,
            if (bucket == "entries") "application/json" else "application/octet-stream",
            temporaryName,
        ) ?: throw FileNotFoundException("Could not create temporary sync file.")
        contentResolver.openOutputStream(temporaryUri, "w")?.use {
            it.write(bytes)
            it.flush()
        } ?: throw FileNotFoundException("Could not write temporary sync file.")

        var movedOld: Uri? = null
        try {
            if (currentTarget != null) {
                findChild(treeUri, directory.documentId, backupName)?.let { deleteDocument(it.uri) }
                movedOld = DocumentsContract.renameDocument(
                    contentResolver,
                    currentTarget.uri,
                    backupName,
                ) ?: throw FileNotFoundException("Provider cannot stage the previous file.")
            }
            DocumentsContract.renameDocument(contentResolver, temporaryUri, name)
                ?: throw FileNotFoundException("Provider cannot promote the complete file.")
            movedOld?.let { deleteDocument(it) }
            return true
        } catch (error: Exception) {
            if (findChild(treeUri, directory.documentId, name) == null && movedOld != null) {
                DocumentsContract.renameDocument(contentResolver, movedOld, name)
            }
            throw error
        }
    }

    private fun requireAvailable(treeUri: Uri) {
        if (!hasPersistedReadWritePermission(treeUri)) {
            throw SecurityException("Persisted read/write permission is unavailable.")
        }
    }

    private fun ensureSyncDirectory(treeUri: Uri, bucket: String): DocumentInfo {
        val root = queryDocument(rootDocumentUri(treeUri))
            ?: throw FileNotFoundException("The selected tree no longer exists.")
        val sync = findChild(treeUri, root.documentId, "diary-sync")
            ?: createDirectory(treeUri, root.documentId, "diary-sync")
        return findChild(treeUri, sync.documentId, bucket)
            ?: createDirectory(treeUri, sync.documentId, bucket)
    }

    private fun createDirectory(treeUri: Uri, parentId: String, name: String): DocumentInfo {
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, parentId)
        val created = DocumentsContract.createDocument(
            contentResolver,
            parentUri,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name,
        ) ?: throw FileNotFoundException("Could not create sync directory.")
        return queryDocument(created) ?: throw FileNotFoundException("Created directory is unavailable.")
    }

    private fun findChild(treeUri: Uri, parentId: String, name: String): DocumentInfo? =
        queryChildren(treeUri, parentId).firstOrNull { it.displayName == name }

    private fun queryChildren(treeUri: Uri, parentId: String): List<DocumentInfo> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        val result = mutableListOf<DocumentInfo>()
        contentResolver.query(childrenUri, DOCUMENT_COLUMNS, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(0)
                result.add(
                    DocumentInfo(
                        documentId,
                        cursor.getString(1),
                        cursor.getString(2),
                        DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId),
                    ),
                )
            }
        }
        return result
    }

    private fun queryDocument(uri: Uri): DocumentInfo? {
        contentResolver.query(uri, DOCUMENT_COLUMNS, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                return DocumentInfo(cursor.getString(0), cursor.getString(1), cursor.getString(2), uri)
            }
        }
        return null
    }

    private fun rootDocumentUri(treeUri: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )

    private fun deleteDocument(uri: Uri) {
        DocumentsContract.deleteDocument(contentResolver, uri)
    }

    private data class DocumentInfo(
        val documentId: String,
        val displayName: String,
        val mimeType: String,
        val uri: Uri,
    )

    companion object {
        private val DOCUMENT_COLUMNS = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
    }

    private fun openNotificationSettings(): Boolean {
        return try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                }
            } else {
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                )
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
