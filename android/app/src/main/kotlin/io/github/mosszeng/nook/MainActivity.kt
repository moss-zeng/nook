package io.github.mosszeng.nook

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import jcifs.CIFSContext
import jcifs.context.BaseContext
import jcifs.config.PropertyConfiguration
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import java.util.Properties
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CHANNEL = "nook/smb"

    // 缓存 CIFSContext，避免每次新建连接
    private var cachedCtx: CIFSContext? = null
    private var cachedKey: String? = null

    private fun ctxFor(user: String, pass: String): CIFSContext {
        val key = "$user:$pass"
        val existing = cachedCtx
        if (existing != null && cachedKey == key) return existing
        val props = Properties().apply {
            setProperty("jcifs.smb.client.minVersion", "SMB202")
            setProperty("jcifs.smb.client.maxVersion", "SMB311")
            // 连接复用与超时，避免连接堆积
            setProperty("jcifs.smb.client.soTimeout", "35000")
            setProperty("jcifs.smb.client.connTimeout", "10000")
            setProperty("jcifs.smb.client.sessionTimeout", "35000")
            setProperty("jcifs.smb.client.responseTimeout", "30000")
            setProperty("jcifs.smb.client.maxRequestRetries", "1")
        }
        val ctx = BaseContext(PropertyConfiguration(props))
            .withCredentials(NtlmPasswordAuthenticator("", user, pass))
        cachedCtx = ctx
        cachedKey = key
        return ctx
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listShares" -> {
                        val host = call.argument<String>("host")!!
                        val user = call.argument<String>("user")!!
                        val pass = call.argument<String>("pass")!!
                        thread {
                            try {
                                val ctx = ctxFor(user, pass)
                                val hiddenShares = setOf("IPC$", "ADMIN$", "print$")
                                val shares = SmbFile("smb://$host/", ctx).use { root ->
                                    root.listFiles()
                                        .map { it.name.trimEnd('/') }
                                        .filter { name ->
                                            name !in hiddenShares &&
                                            !name.endsWith("$") &&
                                            !name.startsWith(".") &&
                                            !name.startsWith("_")
                                        }
                                }
                                runOnUiThread { result.success(shares) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SMB_ERR", e.message, null) }
                            }
                        }
                    }
                    "list" -> {
                        val host = call.argument<String>("host")!!
                        val user = call.argument<String>("user")!!
                        val pass = call.argument<String>("pass")!!
                        val path = call.argument<String>("path") ?: ""
                        thread {
                            try {
                                val ctx = ctxFor(user, pass)
                                val names = SmbFile("smb://$host/$path/", ctx).use { dir ->
                                    dir.listFiles()
                                        .filter { f ->
                                            // 按 SMB 属性自动过滤 Windows 隐藏/系统文件
                                            // （$RECYCLE.BIN、System Volume Information、
                                            //  desktop.ini、Thumbs.db 等都带 hidden/system 属性）。
                                            // 不再按名字手动维护名单；. 开头的自建文件夹
                                            // （.covers/.gallery）没有 hidden 属性，会保留。
                                            val attr = try { f.attributes } catch (e: Exception) { 0 }
                                            val isHidden = (attr and SmbFile.ATTR_HIDDEN) != 0
                                            val isSystem = (attr and SmbFile.ATTR_SYSTEM) != 0
                                            !isHidden && !isSystem
                                        }
                                        .map {
                                            if (it.isDirectory) "[D] " + it.name.trimEnd('/')
                                            else "[F] " + it.name
                                        }
                                }
                                runOnUiThread { result.success(names) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SMB_ERR", e.message, null) }
                            }
                        }
                    }
                    "readFile" -> {
                        val host = call.argument<String>("host")!!
                        val user = call.argument<String>("user")!!
                        val pass = call.argument<String>("pass")!!
                        val path = call.argument<String>("path")!!
                        thread {
                            try {
                                val ctx = ctxFor(user, pass)
                                val text = SmbFile("smb://$host/$path", ctx).use { f ->
                                    if (!f.exists()) null
                                    else f.inputStream.use {
                                        it.bufferedReader(Charsets.UTF_8).readText()
                                    }
                                }
                                runOnUiThread { result.success(text) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SMB_ERR", e.message, null) }
                            }
                        }
                    }
                    "writeFile" -> {
                        val host = call.argument<String>("host")!!
                        val user = call.argument<String>("user")!!
                        val pass = call.argument<String>("pass")!!
                        val path = call.argument<String>("path")!!
                        val content = call.argument<String>("content")!!
                        thread {
                            try {
                                val ctx = ctxFor(user, pass)
                                SmbFile("smb://$host/$path", ctx).use { f ->
                                    f.outputStream.use {
                                        it.write(content.toByteArray(Charsets.UTF_8))
                                    }
                                }
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SMB_ERR", e.message, null) }
                            }
                        }
                    }
                    "readImage" -> {
                        val host = call.argument<String>("host")!!
                        val user = call.argument<String>("user")!!
                        val pass = call.argument<String>("pass")!!
                        val path = call.argument<String>("path")!!
                        thread {
                            try {
                                val ctx = ctxFor(user, pass)
                                val bytes = SmbFile("smb://$host/$path", ctx).use { f ->
                                    if (!f.exists()) null
                                    else f.inputStream.use { it.readBytes() }
                                }
                                runOnUiThread { result.success(bytes) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SMB_ERR", e.message, null) }
                            }
                        }
                    }
                    "readImageHeader" -> {
                        val host = call.argument<String>("host")!!
                        val user = call.argument<String>("user")!!
                        val pass = call.argument<String>("pass")!!
                        val path = call.argument<String>("path")!!
                        // 只读文件前 maxBytes 字节（图片头部已含宽高），默认 65536
                        val maxBytes = call.argument<Int>("maxBytes") ?: 65536
                        thread {
                            try {
                                val ctx = ctxFor(user, pass)
                                val bytes = SmbFile("smb://$host/$path", ctx).use { f ->
                                    if (!f.exists()) null
                                    else f.inputStream.use { input ->
                                        val buf = ByteArray(maxBytes)
                                        var off = 0
                                        // 循环读直到填满 maxBytes 或流结束（只读头部，不读整图）
                                        while (off < maxBytes) {
                                            val n = input.read(buf, off, maxBytes - off)
                                            if (n < 0) break
                                            off += n
                                        }
                                        if (off == maxBytes) buf else buf.copyOf(off)
                                    }
                                }
                                runOnUiThread { result.success(bytes) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SMB_ERR", e.message, null) }
                            }
                        }
                    }
                    "openExternal" -> {
                        val host = call.argument<String>("host")!!
                        val user = call.argument<String>("user")!!
                        val pass = call.argument<String>("pass")!!
                        val path = call.argument<String>("path")!!
                        try {
                            val encUser = java.net.URLEncoder.encode(user, "UTF-8")
                            val encPass = java.net.URLEncoder.encode(pass, "UTF-8")
                            val smbUrl = "smb://$encUser:$encPass@$host/$path"
                            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW)
                            intent.setDataAndType(android.net.Uri.parse(smbUrl), "video/*")
                            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(
                                android.content.Intent.createChooser(intent, "Play with")
                                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_ERR", e.message, null)
                        }
                    }
                    "move" -> {
                        val host = call.argument<String>("host")!!
                        val user = call.argument<String>("user")!!
                        val pass = call.argument<String>("pass")!!
                        val from = call.argument<String>("from")!!  // 相对：share/.../名字
                        val to = call.argument<String>("to")!!      // 目标完整：share/.../名字
                        thread {
                            try {
                                val ctx = ctxFor(user, pass)
                                val src = SmbFile("smb://$host/$from", ctx)
                                val dst = SmbFile("smb://$host/$to", ctx)
                                if (dst.exists()) {
                                    runOnUiThread { result.error("EXISTS", "Target already exists", null) }
                                } else {
                                    src.renameTo(dst)
                                    runOnUiThread { result.success(true) }
                                }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SMB_ERR", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}