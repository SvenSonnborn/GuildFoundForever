# Runs the Guild Found Forever tests outside the game: MoonSharp (a Lua interpreter for .NET) loads
# stubs.lua (a minimal WoW API), then the addon files in TOC order, then tests.lua.
#   .\tests\run.ps1         failures and the summary
#   .\tests\run.ps1 -All    every check
# Exit code 1 if a check fails or the addon does not load.
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [switch]$All
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# MoonSharp 2.0.0 from NuGet, downloaded once into tests\.moonsharp (not part of the repository).
$dll = Join-Path $here '.moonsharp\MoonSharp.Interpreter.dll'
if (-not (Test-Path $dll)) {
    $cache = Join-Path $here '.moonsharp'
    New-Item -ItemType Directory -Force $cache | Out-Null
    $package = Join-Path $cache 'moonsharp.nupkg.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/MoonSharp/2.0.0' -OutFile $package -UseBasicParsing
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($package)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'lib/net40-client/MoonSharp.Interpreter.dll' }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dll, $true)
    } finally {
        $zip.Dispose()
    }
}
Add-Type -Path $dll

$lua = New-Object MoonSharp.Interpreter.Script([MoonSharp.Interpreter.CoreModules]::Preset_Complete)
function Invoke-Lua([scriptblock]$block, [string]$what) {
    try { & $block }
    catch {
        $ex = $_.Exception
        while ($ex.InnerException) { $ex = $ex.InnerException }
        $msg = $ex.Message
        if ($ex -is [MoonSharp.Interpreter.InterpreterException] -and $ex.DecoratedMessage) { $msg = $ex.DecoratedMessage }
        Write-Output "ABORTED in ${what}: $msg"
        exit 1
    }
}

Invoke-Lua { [void]$lua.DoString([IO.File]::ReadAllText((Join-Path $here 'stubs.lua')), $null, 'stubs.lua') } 'stubs.lua'
$ns = $lua.Globals.Get('NS')
$addonName = [MoonSharp.Interpreter.DynValue]::NewString('GuildFoundForever')
$files = Get-Content (Join-Path $Root 'GuildFoundForever.toc') | Where-Object { $_ -match '\.lua$' }
foreach ($file in $files) {
    Invoke-Lua {
        $chunk = $lua.LoadString([IO.File]::ReadAllText((Join-Path $Root $file)), $null, $file)
        [void]$lua.Call($chunk, [MoonSharp.Interpreter.DynValue[]]@($addonName, $ns))
    } $file
}
$result = $null
Invoke-Lua { $script:result = $lua.DoString([IO.File]::ReadAllText((Join-Path $here 'tests.lua')), $null, 'tests.lua').String } 'tests.lua'

$lines = $result -split "`n"
if ($All) {
    $lines
} else {
    $lines | Where-Object { $_ -match '^FAIL|checks, \d+ failed$' }
}
if ($lines[-1] -notmatch ', 0 failed$') {
    exit 1
}
