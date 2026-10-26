param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)

# 只补全本进程环境，避免工具终端缺少 Windows 变量引发 Winsock 10106。
if (-not $env:SystemRoot) { $env:SystemRoot = 'C:\Windows' }
if (-not $env:windir) { $env:windir = $env:SystemRoot }
if (-not $env:ComSpec) { $env:ComSpec = Join-Path $env:SystemRoot 'System32\cmd.exe' }
if (-not ${env:ProgramFiles(x86)}) { ${env:ProgramFiles(x86)} = 'C:\Program Files (x86)' }
if (-not $env:ProgramFiles) { $env:ProgramFiles = 'C:\Program Files' }
if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local' }
if (-not $env:APPDATA) { $env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming' }

$projectPath = Split-Path -Parent $PSScriptRoot
$sdkLine = Get-Content (Join-Path $projectPath 'android\local.properties') | Where-Object { $_ -like 'flutter.sdk=*' } | Select-Object -First 1
$flutterSdkPath = $sdkLine.Substring('flutter.sdk='.Length).Replace('\\', '\')
if (-not (Test-Path -LiteralPath (Join-Path $flutterSdkPath 'bin\flutter.bat'))) { throw '请先在 android/local.properties 配置 flutter.sdk' }
$env:FLUTTER_ROOT = $flutterSdkPath
$env:Path = (Join-Path $flutterSdkPath 'bin') + ';' + $env:Path
if (-not $env:ANDROID_HOME -and (Test-Path -LiteralPath 'E:\Android\Sdk')) { $env:ANDROID_HOME = 'E:\Android\Sdk' }
if (-not $env:PUB_CACHE -and (Test-Path -LiteralPath 'E:\flutter\pub_cache')) { $env:PUB_CACHE = 'E:\flutter\pub_cache' }
if (-not $env:GRADLE_USER_HOME -and (Test-Path -LiteralPath 'E:\Gradle')) { $env:GRADLE_USER_HOME = 'E:\Gradle' }
$env:PUB_HOSTED_URL = 'https://mirrors.tuna.tsinghua.edu.cn/dart-pub/'
# master SDK 的当日引擎资源在镜像中可能尚未同步，资源走官方源；Dart 包仍使用清华镜像。
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.googleapis.com'
# 开发机代理不应接管本机调试服务、Flutter 测试 VM 或本地 IM 长连接。
$env:NO_PROXY = 'localhost,127.0.0.1,::1,10.0.2.2' + $(if ($env:NO_PROXY) { ',' + $env:NO_PROXY } else { '' })
$env:no_proxy = $env:NO_PROXY
if ($env:HTTPS_PROXY) {
    $buildProxy = [Uri]$env:HTTPS_PROXY
    if ($buildProxy.Scheme -eq 'http' -and -not $buildProxy.UserInfo) {
        $env:GRADLE_OPTS = "$env:GRADLE_OPTS -Dhttps.proxyHost=$($buildProxy.Host) -Dhttps.proxyPort=$($buildProxy.Port) -Dhttp.proxyHost=$($buildProxy.Host) -Dhttp.proxyPort=$($buildProxy.Port)"
    }
}
if (-not $FlutterArguments) { $FlutterArguments = @('doctor') }

Push-Location $projectPath
try { & (Join-Path $flutterSdkPath 'bin\flutter.bat') @FlutterArguments; $flutterExitCode = $LASTEXITCODE }
finally { Pop-Location }
exit $flutterExitCode
