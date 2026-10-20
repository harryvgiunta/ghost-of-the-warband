$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$version = '4.7.2-stable'
$engineName = "Godot_v${version}_win64.exe"
$consoleName = "Godot_v${version}_win64_console.exe"
$runtime = Join-Path $PSScriptRoot '.runtime'
$install = Join-Path $runtime 'godot'
$engine = Join-Path $install $engineName
$console = Join-Path $install $consoleName
$expectedHash = '731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953'
$url = "https://github.com/godotengine/godot/releases/download/$version/$engineName.zip"

try {
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'This setup installs the Windows x64 build. Install Godot manually for your platform.'
    }
    if ((Test-Path -LiteralPath $engine) -and (Test-Path -LiteralPath $console)) {
        $reported = (& $console --version | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $reported.StartsWith('4.7.2.stable.')) {
            Write-Host "Godot is already ready: $reported"
            exit 0
        }
        throw 'The existing .runtime/godot installation is not the expected engine. Remove that managed folder and run Setup.cmd again.'
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Path $runtime -Force | Out-Null
    $staging = Join-Path $runtime ('.install-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging | Out-Null
    try {
        $archive = Join-Path $staging 'godot.zip'
        Write-Host "Downloading Godot $version from the official GitHub release..."
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
        $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw 'Godot download checksum mismatch. Nothing was installed.'
        }
        $extracted = Join-Path $staging 'extracted'
        Expand-Archive -LiteralPath $archive -DestinationPath $extracted
        $downloadedConsole = Join-Path $extracted $consoleName
        $downloadedEngine = Join-Path $extracted $engineName
        if (-not (Test-Path -LiteralPath $downloadedEngine) -or -not (Test-Path -LiteralPath $downloadedConsole)) {
            throw 'The official archive did not contain the expected engine executables.'
        }
        $reported = (& $downloadedConsole --version | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $reported.StartsWith('4.7.2.stable.')) {
            throw 'The downloaded Godot executable failed its version check.'
        }
        New-Item -ItemType Directory -Path $install -Force | Out-Null
        Move-Item -LiteralPath $downloadedEngine -Destination $engine -Force
        Move-Item -LiteralPath $downloadedConsole -Destination $console -Force
        Write-Host "Ready: $reported"
        Write-Host 'Run Arena.cmd for multiplayer or Play.cmd for the frontier.'
    }
    finally {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}
catch {
    Write-Error $_
    exit 1
}
