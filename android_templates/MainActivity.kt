package com.bichocutela.cineshow

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

object UpdateFiles {
    fun prefs(context: Context) = context.getSharedPreferences("cineshow_updates", Context.MODE_PRIVATE)
    fun directory(context: Context) = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        ?: throw IllegalStateException("Armazenamento indisponível"), "updates")
    fun clear(context: Context) {
        val p = prefs(context)
        val id = p.getLong("id", -1)
        if (id >= 0) (context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager).remove(id)
        directory(context).listFiles()?.filter { it.extension == "apk" }?.forEach { it.delete() }
        p.edit().clear().apply()
    }
    fun cleanInstalled(context: Context) {
        val p = prefs(context)
        val installed = context.packageManager.getPackageInfo(context.packageName, 0).versionName
        if (p.getString("version", "") == installed) clear(context)
    }
}

class UpdateInstalledReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) UpdateFiles.cleanInstalled(context)
    }
}

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var waitingPermission = false
    private val downloads get() = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val prefs get() = UpdateFiles.prefs(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        UpdateFiles.cleanInstalled(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cineshow/playback")
            .setMethodCallHandler { call, result ->
                if (call.method == "screenAwake") {
                    if (call.argument<Boolean>("enabled") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                } else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cineshow/updates")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            val url = call.argument<String>("url") ?: error("URL ausente")
                            val version = call.argument<String>("version") ?: error("Versão ausente")
                            val sha = call.argument<String>("sha256") ?: error("Hash ausente")
                            require(version.matches(Regex("[0-9]+\\.[0-9]+\\.[0-9]+")))
                            require(sha.matches(Regex("[0-9a-f]{64}")))
                            require(url == "https://github.com/bichocutela/CINESHOW/releases/download/v$version/CINESHOW-v$version.apk")
                            UpdateFiles.clear(this)
                            UpdateFiles.directory(this).mkdirs()
                            val name = "CINESHOW-v$version.apk"
                            val request = DownloadManager.Request(Uri.parse(url))
                                .setTitle("Atualização CINESHOW $version")
                                .setDescription("Baixando nova versão")
                                .setMimeType("application/vnd.android.package-archive")
                                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                                .setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, "updates/$name")
                            val id = downloads.enqueue(request)
                            prefs.edit().putLong("id", id).putString("version", version)
                                .putString("sha256", sha).putString("name", name).apply()
                            result.success(null)
                        }
                        "status" -> {
                            val status = downloadStatus()
                            if (status["state"] == "failed") UpdateFiles.clear(this)
                            result.success(status)
                        }
                        "cancel" -> { UpdateFiles.clear(this); result.success(null) }
                        "install" -> validateAndInstall(result)
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("UPDATE", e.message ?: "Falha na atualização", null)
                }
            }
    }

    private fun downloadStatus(): Map<String, Any> {
        val id = prefs.getLong("id", -1)
        if (id < 0) return mapOf("state" to "idle")
        downloads.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
            if (cursor == null || !cursor.moveToFirst()) return mapOf("state" to "failed")
            fun value(column: String) = cursor.getLong(cursor.getColumnIndexOrThrow(column))
            val status = value(DownloadManager.COLUMN_STATUS).toInt()
            val state = when (status) {
                DownloadManager.STATUS_SUCCESSFUL -> "ready"
                DownloadManager.STATUS_FAILED -> "failed"
                DownloadManager.STATUS_PAUSED -> "paused"
                else -> "downloading"
            }
            return mapOf("state" to state, "bytes" to value(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                "total" to value(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                "version" to (prefs.getString("version", "") ?: ""))
        }
    }

    @Suppress("DEPRECATION")
    private fun validateApk(): File {
        check(downloadStatus()["state"] == "ready") { "O download ainda não terminou" }
        val file = File(UpdateFiles.directory(this), prefs.getString("name", "") ?: "")
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) { val read = input.read(buffer); if (read < 0) break; hash.update(buffer, 0, read) }
        }
        val digest = hash.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
        check(digest == prefs.getString("sha256", "")) { "APK incompleto ou inválido. Baixe novamente." }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val apk = packageManager.getPackageArchiveInfo(file.absolutePath, flags) ?: error("APK inválido")
        val installed = packageManager.getPackageInfo(packageName, flags)
        check(apk.packageName == packageName && apk.versionName == prefs.getString("version", "")) { "Aplicativo ou versão incorretos" }
        val newCode = if (Build.VERSION.SDK_INT >= 28) apk.longVersionCode else apk.versionCode.toLong()
        val oldCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        check(newCode > oldCode) { "Esta versão já está instalada" }
        val newSignatures = if (Build.VERSION.SDK_INT >= 28) apk.signingInfo?.apkContentsSigners else apk.signatures
        val oldSignatures = if (Build.VERSION.SDK_INT >= 28) installed.signingInfo?.apkContentsSigners else installed.signatures
        check(!newSignatures.isNullOrEmpty() && !oldSignatures.isNullOrEmpty() &&
            newSignatures.map { it.toCharsString() }.toSet() == oldSignatures.map { it.toCharsString() }.toSet()) { "Assinatura da atualização não corresponde ao CINESHOW" }
        return file
    }

    private fun validateAndInstall(result: MethodChannel.Result?) {
        worker.execute {
            try {
                val file = validateApk()
                runOnUiThread {
                    try {
                        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                            waitingPermission = true
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                            result?.success("permission")
                        } else {
                            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                            startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                            result?.success("installer")
                        }
                    } catch (e: Exception) { result?.error("INSTALL", e.message, null) }
                }
            } catch (e: Exception) {
                UpdateFiles.clear(this)
                runOnUiThread { result?.error("VERIFY", e.message, null) }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        UpdateFiles.cleanInstalled(this)
        if (waitingPermission) {
            waitingPermission = false
            if (Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()) validateAndInstall(null)
        }
    }
}
