param(
    [switch]$Nightly,
    [switch]$Debug,
    [switch]$NoGui,
    [switch]$NoIntegrate,
    [switch]$Force,
    [string]$Dest
)

$ErrorActionPreference = "Stop"

if ($env:NIGHTLY -and $env:NIGHTLY -ne "0") { $Nightly = $true }
if ($env:DEBUG -and $env:DEBUG -ne "0") { $Debug = $true }
if ($env:NO_GUI -and $env:NO_GUI -ne "0") { $NoGui = $true }
if ($env:NO_INTEGRATE -and $env:NO_INTEGRATE -ne "0") { $NoIntegrate = $true }
if ($env:FORCE_UPDATE -and $env:FORCE_UPDATE -ne "0") { $Force = $true }
if ($env:DEST) { $Dest = $env:DEST }
# debug builds are only published for nightlies
if ($Debug) { $Nightly = $true }
if ($NoGui) { $NoIntegrate = $true }

function Stop-Install($message) {
    Write-Host $message
    $global:LASTEXITCODE = 1
    if ($PSCommandPath) { exit 1 }
}

function Get-LatestTag($uri) {
    try {
        $release = Invoke-RestMethod -Uri $uri -ErrorAction Stop
        if ($release.tag_name) { return $release.tag_name }
    } catch { }
    return $null
}

function Get-Download($uri, $out) {
    try {
        Invoke-WebRequest -Uri $uri -OutFile $out -ErrorAction Stop
        return $true
    } catch {
        # a failed download can leave a truncated file behind
        Remove-Item $out -Force -ErrorAction SilentlyContinue
        return $false
    }
}

if ($Nightly) {
    $repo = "neurocyte/flow-nightly"
    $title = "flow nightly build"
} else {
    $repo = "neurocyte/flow"
    $title = "flow"
}
if ($Debug) {
    $title = "$title (debug)"
}

if ($Dest) {
    $install_dir = $Dest
} else {
    $install_dir = "$env:APPDATA\flow\bin"
}

$version = Get-LatestTag "https://codeberg.org/api/v1/repos/$repo/releases/latest"
if (-not $version) { $version = Get-LatestTag "https://api.github.com/repos/$repo/releases/latest" }
if (-not $version) { $version = Get-LatestTag "https://git.flow-control.dev/api/v1/repos/$repo/releases/latest" }
if (-not $version) {
    Stop-Install "failed to fetch $title latest version from codeberg, github or flow-control.dev"
    return
}
$title_updater = "$title updater"

$existing_flow = Join-Path -Path $install_dir -ChildPath "flow.exe"
if (-not $Force -and (Test-Path $existing_flow)) {
    $existing_version_output = & $existing_flow --version 2>&1 | Out-String
    $existing_version_lines = $existing_version_output -split "[\r\n]+" | Where-Object { $_ -match '^\s*version:\s*(.+?)\s*$' }
    if ($existing_version_lines -and $matches) {
        $existing_version = $matches[1]
        if ($version -eq $existing_version) {
            Write-Host "$title is up-to-date (version $version @ $install_dir)"
            return
        }
    }
}

$title = "$title $version"

switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64"  { $arch = "x86_64" }
    "ARM64"  { $arch = "aarch64" }
    default  {
        Stop-Install "unknown architecture: $($env:PROCESSOR_ARCHITECTURE)"
        return
    }
}

$filename = "flow-$version-windows-$arch"
if ($Debug) {
    $filename = "$filename-debug"
}
$filename = "$filename.zip"

$stage = Join-Path $env:TEMP "flow-install-$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $stage | Out-Null
$archive = Join-Path $stage $filename

$url = "https://codeberg.org/$repo/releases/download/$version/$filename"
$url_gh = "https://github.com/$repo/releases/download/$version/$filename"

Write-Host "downloading $title..."
if (-not (Get-Download $url $archive) -and -not (Get-Download $url_gh $archive)) {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    Stop-Install "failed to download $filename from codeberg or github"
    return
}

# sanity check
$filesize = (Get-Item $archive).Length
if ($filesize -lt 16384) {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    Stop-Install "downloaded file appears to be invalid (size: $filesize bytes)"
    return
}

echo "installing $title to $install_dir ..."
Expand-Archive -Path $archive -DestinationPath $stage -Force
Remove-Item $archive

$staged_gui = Join-Path $stage "flow-gui.exe"
if ($NoGui) {
    Remove-Item $staged_gui -Force -ErrorAction SilentlyContinue
} elseif (-not (Test-Path $staged_gui)) {
    Write-Host "note: this build does not include flow-gui"
    $NoIntegrate = $true
}

if (-not (Test-Path $install_dir)) {
    Write-Host "creating installation directory: $install_dir"
    New-Item -ItemType Directory -Path $install_dir | Out-Null
}

Copy-Item (Join-Path $stage "*") $install_dir -Recurse -Force
Remove-Item $stage -Recurse -Force

if (-not $NoIntegrate) {
    $gui = Join-Path $install_dir "flow-gui.exe"
    $programs = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $shortcut_path = Join-Path $programs "Flow Control.lnk"
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut_path)
    $shortcut.TargetPath = $gui
    $shortcut.WorkingDirectory = $install_dir
    $shortcut.Description = "Flow Control"
    $shortcut.Save()
    Write-Host "created start menu shortcut $shortcut_path"
}

echo "installing $title_updater to $install_dir\update-flow.ps1 ..."
Invoke-WebRequest -Uri "https://flow-control.dev/install.ps1" -OutFile "$install_dir\install.ps1"
# update-flow repeats this install with the same options, so that updating a
# nightly does not silently switch to a release. -Force is deliberately not
# repeated: a one-off force should not make every future update re-download
$switches = @()
if ($Nightly) { $switches += "-Nightly" }
if ($Debug) { $switches += "-Debug" }
if ($NoGui) { $switches += "-NoGui" } elseif ($NoIntegrate) { $switches += "-NoIntegrate" }
$switches += "-Dest `"$install_dir`""
$updater_script = @"
# generated by the flow installer
& "`$PSScriptRoot\install.ps1" $($switches -join ' ')
"@
Set-Content -Path "$install_dir\update-flow.ps1" -Value $updater_script

echo "$title installed successfully to $install_dir"

$current_path = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($current_path -notlike "*$install_dir*") {
    $response = Read-Host "do you want to add $install_dir to your PATH? (y/n)"
    if ($response -eq "y") {
        $newPath = "$current_path;$install_dir"
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "added $install_dir to PATH"
        Write-Host "close your terminal for changes to take effect"
    }
}
