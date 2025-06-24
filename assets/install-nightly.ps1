$ErrorActionPreference = "Stop"

$repo = "neurocyte/flow-nightly"
$title = "flow nightly build"
$updater = "install-nightly"

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
$version = $release.tag_name
$title_updater = "$title updater"
$install_dir = "$env:APPDATA\flow\bin"

$existing_flow = Join-Path -Path $install_dir -ChildPath "flow.exe"
if (Test-Path $existing_flow) {
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
        Write-Host "unknown architecture: $($env:PROCESSOR_ARCHITECTURE)"
        $LASTEXITCODE = 1
        return
    }
}

$filename = "flow-$version-windows-$arch.zip"

if (-not (Test-Path $install_dir)) {
    Write-Host "creating installation directory: $install_dir"
    New-Item -ItemType Directory -Path $install_dir | Out-Null
}

Write-Host "downloading $title..."
Invoke-WebRequest -Uri "https://github.com/$repo/releases/download/$version/$filename" -OutFile "$install_dir\$filename"

echo "installing $title to $install_dir ..."
Expand-Archive -Path "$install_dir\$filename" -DestinationPath $install_dir -Force
Remove-Item "$install_dir\$filename"

echo "installing $title_updater to $install_dir\update-flow.ps1 ..."
Invoke-WebRequest -Uri "https://flow-control.dev/$updater.ps1" -OutFile "$install_dir\update-flow.ps1"

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
