# install_apk.ps1 — Windows 版导出并安装调试 APK（替代 macOS 的 install_apk.sh）
#
# 用法：
#   powershell -File install_apk.ps1              # 导出 + 安装到已连接设备
#   powershell -File install_apk.ps1 -Launch      # 安装后直接启动
#   powershell -File install_apk.ps1 -GodotBin D:\path\Godot_console.exe -AdbBin D:\path\adb.exe
#
# 若系统策略拦截 .ps1：先执行一次 Set-ExecutionPolicy RemoteSigned -Scope CurrentUser，
# 之后直接 .\install_apk.ps1 即可。
#
# 一次性环境准备（脚本会逐项预检并给出提示）：
#   1. Android SDK：安装 Android Studio 或 cmdline-tools，需含 platform-tools / build-tools / platforms;android-35
#   2. JDK 17：Godot 4.7 Gradle 构建要求；脚本按 JAVA_HOME -> 常见安装目录 顺序探测
#   3. Godot 导出模板：编辑器内"项目 -> 安装 Android 导出模板"（对应 4.7.stable）
#   4. Godot 编辑器设置中 export/android/android_sdk_path 指向 SDK 根目录

param(
    [string]$GodotBin = "",
    [string]$AdbBin = "",
    [switch]$Launch
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$PresetName = "Android"
$ApkPath = "build\eggs-debug.apk"
$PackageName = "com.zihenggao.eggs"

function Fail([string]$message, [string]$hint = "") {
    Write-Host "error: $message" -ForegroundColor Red
    if ($hint) { Write-Host $hint -ForegroundColor Yellow }
    exit 1
}

function Find-Executable([string]$override, [string]$envValue, [string[]]$candidates) {
    if ($override -and (Test-Path $override)) { return $override }
    if ($envValue -and (Test-Path $envValue)) { return $envValue }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return ""
}

# --- Godot 二进制 ---
$Godot = Find-Executable $GodotBin $env:GODOT_BIN @(
    "D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
    (Get-Command godot.exe -ErrorAction SilentlyContinue).Source,
    (Get-Command godot.console.exe -ErrorAction SilentlyContinue).Source
)
if (-not $Godot) {
    Fail "Godot binary not found." "用 -GodotBin 或环境变量 GODOT_BIN 指向 Godot 4.7 console 可执行文件。"
}

# --- adb ---
$adbCandidates = @()
if ($env:ANDROID_SDK_ROOT) { $adbCandidates += Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe" }
if ($env:ANDROID_HOME) { $adbCandidates += Join-Path $env:ANDROID_HOME "platform-tools\adb.exe" }
$adbCandidates += "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$adbOnPath = Get-Command adb.exe -ErrorAction SilentlyContinue
if ($adbOnPath) { $adbCandidates += $adbOnPath.Source }
$Adb = Find-Executable $AdbBin $env:ADB_BIN $adbCandidates
if (-not $Adb) {
    Fail "adb not found." "安装 Android SDK platform-tools，或用 -AdbBin / ADB_BIN 指定 adb.exe。"
}

# --- JDK 17（Gradle 构建需要；仅对脚本进程注入，不改系统环境） ---
if (-not $env:JAVA_HOME -or -not (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
    $jdk = Get-ChildItem "C:\Program Files\Java", "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "bin\java.exe") } | Select-Object -First 1
    if ($jdk) {
        $env:JAVA_HOME = $jdk.FullName
        $env:Path = (Join-Path $jdk.FullName "bin") + ";" + $env:Path
        Write-Host "JAVA_HOME (进程内): $($jdk.FullName)"
    } else {
        Fail "未找到 JDK。" "Gradle 构建需要 JDK 17：安装 Eclipse Temurin 17 或设置 JAVA_HOME 后重试。"
    }
}

# --- Android SDK 预检 ---
$sdkRoot = $env:ANDROID_SDK_ROOT
if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_HOME }
if (-not $sdkRoot) { $sdkRoot = "$env:LOCALAPPDATA\Android\Sdk" }
if (-not (Test-Path (Join-Path $sdkRoot "build-tools"))) {
    Fail "Android SDK 不完整：$sdkRoot 下缺少 build-tools。" "用 Android Studio SDK Manager 安装 platform-tools / build-tools / platforms;android-35。"
}

# --- 导出模板预检 ---
$templates = "$env:APPDATA\Godot\export_templates\4.7.stable"
if (-not (Test-Path (Join-Path $templates "android_source.zip"))) {
    Fail "Godot 4.7 Android 导出模板未安装。" "编辑器内：项目 -> 安装 Android 导出模板，版本需与 Godot 完全一致（4.7.stable）。"
}

# --- 设备检查 ---
$state = (& $Adb get-state 2>$null)
if ($state -ne "device") {
    Fail "未检测到 Android 设备（adb get-state 失败）。" "检查数据线、USB 调试授权，然后运行：$Adb devices"
}

$godotVersion = (& $Godot --version)
$deviceModel = (& $Adb shell getprop ro.product.model 2>$null)
Write-Host "godot:  $Godot ($godotVersion)"
Write-Host "adb:    $Adb"
Write-Host "device: $(if ($deviceModel) { $deviceModel } else { 'unknown' })"

# --- 导出 ---
New-Item -ItemType Directory -Force -Path "build" | Out-Null
Write-Host "exporting $PresetName -> $ApkPath ..."
& $Godot --headless --path . --export-debug $PresetName $ApkPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ApkPath)) {
    Fail "导出失败（exit=$LASTEXITCODE）。" "完整日志见上方 Godot 输出；常见问题：SDK 路径未在编辑器设置中保存、模板版本不匹配、Gradle 首次联网下载被中断。"
}

# --- 安装 ---
Write-Host "installing $ApkPath ..."
& $Adb install -r $ApkPath
if ($LASTEXITCODE -ne 0) {
    Fail "adb install 失败（exit=$LASTEXITCODE）。" "签名变更时需先卸载旧包：$Adb uninstall $PackageName"
}

Write-Host "done." -ForegroundColor Green
if ($Launch) {
    & $Adb shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
    Write-Host "已启动 $PackageName"
} else {
    Write-Host "启动命令："
    Write-Host "  $Adb shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1"
}
