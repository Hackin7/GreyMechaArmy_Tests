param(
    [ValidateSet('model','sim','bit','all')][string]$Target='all',
    [string]$Resources='/mnt/d/Github/WORK/NUS/EE2026/EE2026_Project_B-MODs/integration_group_basic_tasks/integration_group_basic_tasks.srcs/sources_1/imports/res'
)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    if ($Target -eq 'all') {
        wsl --cd $PSScriptRoot --exec make "RESOURCES=$Resources" sim bit
    } else {
        wsl --cd $PSScriptRoot --exec make "RESOURCES=$Resources" $Target
    }
    if ($LASTEXITCODE -ne 0) { throw 'Paint MNIST build/verification failed' }
} finally {
    Pop-Location
}
