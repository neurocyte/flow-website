param(
    [switch]$Nightly,
    [switch]$Debug,
    [switch]$NoGui,
    [switch]$NoIntegrate,
    [switch]$Force,
    [switch]$AllowDowngrade,
    [switch]$NoVerify,
    [string]$KeyFile,
    [string]$Dest
)

$ErrorActionPreference = "Stop"

$installer_version = 0

if ($env:FLOW_NIGHTLY -and $env:FLOW_NIGHTLY -ne "0") { $Nightly = $true }
if ($env:FLOW_NIGHTLY_DEBUG -and $env:FLOW_NIGHTLY_DEBUG -ne "0") { $Debug = $true }
if ($env:NIGHTLY -and $env:NIGHTLY -ne "0") {
    Write-Host "warning: NIGHTLY is deprecated, use FLOW_NIGHTLY instead"
    $Nightly = $true
}
if ($env:DEBUG -and $env:DEBUG -ne "0") {
    Write-Host "warning: DEBUG is deprecated, use FLOW_NIGHTLY_DEBUG instead"
    $Debug = $true
}
if ($env:NO_GUI -and $env:NO_GUI -ne "0") { $NoGui = $true }
if ($env:NO_INTEGRATE -and $env:NO_INTEGRATE -ne "0") { $NoIntegrate = $true }
if ($env:FORCE_UPDATE -and $env:FORCE_UPDATE -ne "0") { $Force = $true }
if ($env:ALLOW_DOWNGRADE -and $env:ALLOW_DOWNGRADE -ne "0") { $AllowDowngrade = $true }
if ($env:NO_VERIFY -and $env:NO_VERIFY -ne "0") { $NoVerify = $true }
if ($env:KEYFILE) { $KeyFile = $env:KEYFILE }
if ($env:DEST) { $Dest = $env:DEST }
# debug builds are only published for nightlies
if ($Debug) { $Nightly = $true }
if ($NoGui) { $NoIntegrate = $true }

# fingerprint of the key that signs flow releases and this script
$key_fingerprint = "4E6CF7234FFC4E14531074F98EB1E1BB660E3FB9"
$key_url = "https://flow-control.dev/public.gpg"
$state_dir = "$env:APPDATA\flow"

# quote a value for safe inclusion in the generated update-flow.ps1
function Format-PSLiteral($value) {
    return "'" + ($value -replace "'", "''") + "'"
}

# order two flow tags. releases are "vM.m.p"; nightlies are "vM.m.p-<count>-g<hash>"
function Get-VersionKey($tag) {
    if ($tag -notmatch '^v?([0-9]+)(?:\.([0-9]+))?(?:\.([0-9]+))?(?:-([0-9]+)-g[0-9a-fA-F]+)?$') {
        return $null
    }
    return , @([int]"0$($matches[1])", [int]"0$($matches[2])",
               [int]"0$($matches[3])", [int]"0$($matches[4])")
}

# -1 older, 0 same, 1 newer, $null when either tag cannot be ordered
function Compare-FlowVersion($a, $b) {
    $ka = Get-VersionKey $a
    $kb = Get-VersionKey $b
    if ($null -eq $ka -or $null -eq $kb) { return $null }
    for ($i = 0; $i -lt 4; $i++) {
        if ($ka[$i] -lt $kb[$i]) { return -1 }
        if ($ka[$i] -gt $kb[$i]) { return 1 }
    }
    return 0
}

function Get-TagLineage($tag) {
    if ($tag -match '-[0-9]+-g[0-9a-fA-F]+$') { return "nightly" }
    return "release"
}

function Install-File($src, $dst) {
    $dir = Split-Path $dst
    $leaf = Split-Path $dst -Leaf
    Get-ChildItem -Path $dir -Filter "$leaf.old*" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    try {
        Copy-Item $src $dst -Force -ErrorAction Stop
        return
    } catch {
        if (-not (Test-Path $dst)) { throw }
    }
    # several builds can be held at once, so the rename has to be random
    $old = "$dst.old"
    if (Test-Path $old) {
        $old = "$dst.old.$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
    }
    Rename-Item -Path $dst -NewName (Split-Path $old -Leaf) -Force
    Copy-Item $src $dst -Force
}

function Get-FlowVersion($exe) {
    $ErrorActionPreference = "Continue"
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $out = & $exe --version 2>$null | Out-String
    } catch {
        # blocked by antivirus, missing a runtime, not executable at all
        return $null
    }
    foreach ($line in $out -split "[\r\n]+") {
        if ($line -match '^\s*version:\s*(.+?)\s*$') { return $matches[1] }
    }
    return $null
}

function Stop-Install($message) {
    Write-Host $message
    $global:LASTEXITCODE = 1
    if ($PSCommandPath) { exit 1 }
}

function Get-Download($uri, $out) {
    try {
        Invoke-WebRequest -Uri $uri -OutFile $out -ErrorAction Stop
        return $true
    } catch {
        Remove-Item $out -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Test-Signature($file, $sigfile) {
    $ErrorActionPreference = "Continue"
    $PSNativeCommandUseErrorActionPreference = $false
    $status = & $gpgv_bin --keyring $key_path --status-fd 1 $sigfile $file 2>$null
    return [bool]($status | Select-String -Quiet -Pattern "^\[GNUPG:\] VALIDSIG .* $($key_fingerprint)$")
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

$gpgv_bin = ""
if ($NoVerify) {
    Write-Host ""
    Write-Host "########################################################################"
    Write-Host "# WARNING: signature verification is disabled.                         #"
    Write-Host "# Nothing was checked; the download is trusted on TLS alone.           #"
    Write-Host "########################################################################"
    Write-Host ""
} else {
    $gpgv_bin = (Get-Command gpgv -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1).Source
    if (-not $gpgv_bin) {
        Stop-Install @"
error: gpgv is required to verify the download, but was not found

gpgv is gnupg's signature verification tool. install gnupg with

    winget install GnuPG.GnuPG

then open a new terminal so that gpgv is on PATH, and try again, or set
`$env:NO_VERIFY = 1 to install without checking signatures
"@
        return
    }
}

$tmp = Join-Path $env:TEMP "flow-install-$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmp | Out-Null

try {

$key_path = ""
$stored_key = Join-Path $state_dir "public.gpg"
if ($KeyFile) {
    if (-not (Test-Path $KeyFile)) {
        Stop-Install "error: key file `"$KeyFile`" not found"
        return
    }
    $key_path = $KeyFile
    if (-not $NoVerify) { Write-Host "verifying with $key_path" }
} else {
    $fetched_key = Join-Path $tmp "public.gpg"
    if (-not (Get-Download $key_url $fetched_key)) {
        Stop-Install "failed to download the public key from $key_url"
        return
    }
    if ((Test-Path $stored_key) -and
        (Get-FileHash $stored_key).Hash -ne (Get-FileHash $fetched_key).Hash) {
        Stop-Install @"
error: the public key at $key_url does not match $stored_key

the signing key has changed since flow was last installed. this is
expected after a key rotation, but it is also what a compromised
download would look like. verify the new key before continuing:

  gpg --show-keys --with-fingerprint "$stored_key"

then remove $stored_key to accept the new key.
"@
        return
    }
    $key_path = $fetched_key
}

# signed version manifest
$manifest = if ($Nightly) { "version-latest-nightly" } else { "version-latest" }
$manifest_url = "https://flow-control.dev/$manifest"
$manifest_path = Join-Path $tmp $manifest

if (-not (Get-Download $manifest_url $manifest_path)) {
    Stop-Install "failed to fetch the version manifest from $manifest_url"
    return
}

if (-not $NoVerify) {
    if (-not (Get-Download "$manifest_url.sig" "$manifest_path.sig")) {
        Stop-Install "failed to fetch the version manifest signature from $manifest_url.sig"
        return
    }
    if (-not (Test-Signature $manifest_path "$manifest_path.sig")) {
        Stop-Install @"
error: $manifest_url is not signed by $key_fingerprint
refusing to trust the version it names
"@
        return
    }
}

$version = "$(Get-Content $manifest_path -Raw)".Trim()
if (-not $version) {
    Stop-Install "the version manifest at $manifest_url is empty"
    return
}

if ($version -notmatch '^[A-Za-z0-9._+-]+$') {
    Stop-Install "refusing to use an implausible release tag: $version"
    return
}

$title_updater = "$title updater"

$existing_flow = Join-Path -Path $install_dir -ChildPath "flow.exe"
$existing_version = $null
if (Test-Path $existing_flow) { $existing_version = Get-FlowVersion $existing_flow }

if (-not $AllowDowngrade -and $existing_version -and
    (Get-TagLineage $version) -eq (Get-TagLineage $existing_version)) {
    $order = Compare-FlowVersion $version $existing_version
    if ($null -ne $order -and $order -lt 0) {
        Stop-Install @"
error: $version is older than the installed $existing_version

run with -AllowDowngrade to downgrade
"@
        return
    }
}

if (-not $Force -and $existing_version -and $version -eq $existing_version) {
    Write-Host "$title is up-to-date (version $version @ $install_dir)"
    return
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

$unpack = Join-Path $tmp "unpack"
New-Item -ItemType Directory -Path $unpack | Out-Null
$archive = Join-Path $tmp $filename

$url = "https://codeberg.org/$repo/releases/download/$version/$filename"
$url_gh = "https://github.com/$repo/releases/download/$version/$filename"

Write-Host "downloading $title..."
if (-not (Get-Download $url $archive) -and -not (Get-Download $url_gh $archive)) {
    Stop-Install "failed to download $filename from codeberg or github"
    return
}

# sanity check
$filesize = (Get-Item $archive).Length
if ($filesize -lt 16384) {
    Stop-Install "downloaded file appears to be invalid (size: $filesize bytes)"
    return
}

if (-not $NoVerify) {
    $sigfile = "$archive.sig"
    if (-not (Get-Download "$url.sig" $sigfile) -and -not (Get-Download "$url_gh.sig" $sigfile)) {
        Stop-Install "failed to download $filename.sig from codeberg or github"
        return
    }
    if (Test-Signature $archive $sigfile) {
        Write-Host "good signature from $key_fingerprint"
    } else {
        Stop-Install @"
error: signature verification failed for $filename
the download does not carry a valid signature from $key_fingerprint
"@
        return
    }
}

echo "installing $title to $install_dir ..."
Expand-Archive -Path $archive -DestinationPath $unpack -Force

if (-not (Test-Path (Join-Path $unpack "flow.exe"))) {
    Stop-Install "downloaded archive does not contain flow.exe"
    return
}

$unpacked_version = Get-FlowVersion (Join-Path $unpack "flow.exe")
if (-not $unpacked_version) {
    Stop-Install @"
error: could not determine the version of the downloaded flow.exe

it did not run, or it does not report a version. refusing to install
something that cannot be identified
"@
    return
}
if ($unpacked_version -ne $version) {
    Stop-Install @"
error: the archive for $version contains $unpacked_version instead
refusing to install
"@
    return
}

$staged_gui = Join-Path $unpack "flow-gui.exe"
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

foreach ($item in Get-ChildItem $unpack -Recurse) {
    $target = Join-Path $install_dir $item.FullName.Substring($unpack.Length + 1)
    if ($item.PSIsContainer) {
        if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target | Out-Null }
    } else {
        Install-File $item.FullName $target
    }
}

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

if (-not $KeyFile) {
    New-Item -ItemType Directory -Path $state_dir -Force | Out-Null
    Copy-Item $key_path $stored_key -Force
}

} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

echo "installing $title_updater to $install_dir\update-flow.ps1 ..."
Remove-Item "$install_dir\install.ps1" -Force -ErrorAction SilentlyContinue
# update-flow repeats this install with the same options
$switches = @()
if ($Nightly) { $switches += "Nightly = `$true" }
if ($Debug) { $switches += "Debug = `$true" }
if ($NoGui) { $switches += "NoGui = `$true" } elseif ($NoIntegrate) { $switches += "NoIntegrate = `$true" }
if ($KeyFile) { $switches += "KeyFile = $(Format-PSLiteral $KeyFile)" }
$switch_literal = "@{ " + ($switches -join "; ") + " }"
$updater_keyring = if ($KeyFile) { $KeyFile } else { $stored_key }
$updater_head = @"
# generated by the flow installer
`$installer_version = $installer_version
`$fingerprint = $(Format-PSLiteral $key_fingerprint)
`$keyring = $(Format-PSLiteral $updater_keyring)
`$install_dir = $(Format-PSLiteral $install_dir)
`$switches = $switch_literal
"@
$updater_body = @'
$ErrorActionPreference = "Stop"

# -NoVerify does not persist: it has to be asked for on every update
$no_verify = $false
foreach ($arg in $args) { if ($arg -eq "-NoVerify") { $no_verify = $true } }
if ($env:NO_VERIFY -and $env:NO_VERIFY -ne "0") { $no_verify = $true }

$tmp = Join-Path $env:TEMP "flow-update-$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Invoke-WebRequest -Uri "https://flow-control.dev/install.ps1" -OutFile "$tmp\install.ps1"

    if ($no_verify) {
        Write-Host ""
        Write-Host "########################################################################"
        Write-Host "# WARNING: signature verification is disabled.                         #"
        Write-Host "# Nothing was checked; the download is trusted on TLS alone.           #"
        Write-Host "########################################################################"
        Write-Host ""
    } else {
        $gpgv_bin = (Get-Command gpgv -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1).Source
        if (-not $gpgv_bin) {
            Write-Host "error: gpgv is required to verify the installer, but was not found"
            Write-Host ""
            Write-Host "gpgv is gnupg's signature verification tool. install gnupg with"
            Write-Host ""
            Write-Host "    winget install GnuPG.GnuPG"
            Write-Host ""
            Write-Host "then open a new terminal so that gpgv is on PATH, and try again, or"
            Write-Host "re-run with -NoVerify to update without checking signatures"
            exit 1
        }

        if (-not (Test-Path $keyring)) {
            Write-Host "error: $keyring is missing"
            Write-Host "re-install from https://flow-control.dev/install.ps1 to restore it"
            exit 1
        }

        try {
            Invoke-WebRequest -Uri "https://flow-control.dev/install.ps1.sig" `
                -OutFile "$tmp\install.ps1.sig" -ErrorAction Stop
        } catch {
            Write-Host "error: could not fetch the installer signature from"
            Write-Host "https://flow-control.dev/install.ps1.sig"
            Write-Host "refusing to run an unverified installer"
            exit 1
        }

        function Test-Installer($file, $sigfile) {
            $ErrorActionPreference = "Continue"
            $PSNativeCommandUseErrorActionPreference = $false
            $status = & $gpgv_bin --keyring $keyring --status-fd 1 $sigfile $file 2>$null
            return [bool]($status | Select-String -Quiet -Pattern "^\[GNUPG:\] VALIDSIG .* $($fingerprint)$")
        }
        if (-not (Test-Installer "$tmp\install.ps1" "$tmp\install.ps1.sig")) {
            Write-Host "error: the installer at flow-control.dev is not signed by $fingerprint"
            Write-Host "refusing to run it"
            exit 1
        }

        $fetched_version = $null
        foreach ($line in (Get-Content "$tmp\install.ps1")) {
            if ($line -match '^\$installer_version = (\d+)$') {
                $fetched_version = [int]$matches[1]
                break
            }
        }
        if ($null -eq $fetched_version) {
            Write-Host "error: the installer at flow-control.dev does not carry a version"
            Write-Host "refusing to run it"
            exit 1
        }
        if ($fetched_version -lt $installer_version) {
            Write-Host "error: the installer at flow-control.dev is older than the one"
            Write-Host "flow was installed with ($fetched_version < $installer_version)"
            exit 1
        }
    }

    & "$tmp\install.ps1" @switches -Dest $install_dir @args
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
'@
Set-Content -Path "$install_dir\update-flow.ps1" -Value ($updater_head + "`n" + $updater_body)

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
