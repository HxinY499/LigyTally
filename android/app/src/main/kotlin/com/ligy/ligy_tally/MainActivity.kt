package com.ligy.ligy_tally

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用内更新所需的原生能力。
 *
 * 只做三件事：报告当前版本、检查是否允许安装未知应用、拉起系统安装器。
 * 下载与校验都在 Dart 侧完成，这里不碰网络。
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.ligy.ligy_tally/app_update"
        private const val ICON_CHANNEL = "com.ligy.ligy_tally/app_icon"
        private const val FILE_PROVIDER_AUTHORITY = "com.ligy.ligy_tally.update_provider"

        // 桌面图标对应的两个 activity-alias 短名，
        // 保持与 AndroidManifest.xml 里声明的一致。
        private const val ALIAS_DARK = "LauncherDark"
        private const val ALIAS_LIGHT = "LauncherLight"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVersionInfo" -> result.success(readVersionInfo())
                "canInstallPackages" -> result.success(canInstallPackages())
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "缺少 APK 路径", null)
                    } else {
                        installApk(path, result)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ICON_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrent" -> result.success(currentIconKey())
                "setIcon" -> {
                    val key = call.argument<String>("key")
                    if (key.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "缺少图标 key", null)
                    } else {
                        try {
                            applyIcon(key)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SET_ICON_FAILED", e.message ?: "切换图标失败", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** 返回 versionName 与 versionCode，供Dart 侧与线上版本比较。 */
    private fun readVersionInfo(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "versionName" to (info.versionName ?: ""),
            "versionCode" to code,
        )
    }

    /**
     * Android 8.0 起「安装未知应用」是按应用授予的权限，
     * 未授权时直接发安装 Intent 会被系统静默拦下。
     */
    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    /** 跳到本应用的「安装未知应用」开关页，让用户自己打开。 */
    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } else {
            startActivity(
                Intent(Settings.ACTION_SECURITY_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        val apk = File(path)
        if (!apk.exists()) {
            result.error("FILE_NOT_FOUND", "安装包不存在：$path", null)
            return
        }

        try {
            //走 FileProvider 生成 content:// URI；Android 7之后不允许直接传 file://
            val uri = FileProvider.getUriForFile(this, FILE_PROVIDER_AUTHORITY, apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message ?: "拉起安装器失败", null)
        }
    }

    // ---- 桌面图标切换 ------------------------------------------------------

    /**
     * 读取当前生效的 activity-alias。
     *
     * 只关心 dark 是否启用——两个 alias 不允许同时禁用（会导致桌面上应用消失），
     * 所以「非 dark 即 light」。
     */
    private fun currentIconKey(): String {
        val dark = ComponentName(packageName, "$packageName.$ALIAS_DARK")
        val state = packageManager.getComponentEnabledSetting(dark)
        val enabled = when (state) {
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> true // manifest 里 dark 默认 enabled
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            else -> false
        }
        return if (enabled) "dark" else "light"
    }

    /**
     * 切换到指定图标。
     *
     * 关键点：先启用目标 alias，再禁用另一个。反过来做会出现「两个都禁用」
     * 的瞬时状态，某些 launcher 会把应用图标从桌面上移除。
     *
     * DONT_KILL_APP 让 PackageManager 不重启进程——效果一般是桌面刷新
     * 需要几秒才能看到新图标，属正常现象。
     */
    private fun applyIcon(key: String) {
        val (enable, disable) = when (key) {
            "dark" -> ALIAS_DARK to ALIAS_LIGHT
            "light" -> ALIAS_LIGHT to ALIAS_DARK
            else -> throw IllegalArgumentException("未知图标 key: $key")
        }
        val pm = packageManager
        pm.setComponentEnabledSetting(
            ComponentName(packageName, "$packageName.$enable"),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        pm.setComponentEnabledSetting(
            ComponentName(packageName, "$packageName.$disable"),
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
