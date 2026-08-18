# Compatibility shim: the nightly installer is now install.ps1 -Nightly
#
# Existing installs re-download this path from their update-flow.ps1, so this
# runs the merged installer, which then replaces update-flow.ps1 with a wrapper
# that no longer needs this shim. It can be dropped once those have updated.

$ErrorActionPreference = "Stop"

$installer = Invoke-RestMethod -Uri "https://flow-control.dev/install.ps1"
& ([scriptblock]::Create($installer)) -Nightly
