param(
    [string]$Target = "test",
    [string]$ToolchainPrefix = "",
    [string]$Distro = "",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$MakeArgs
)

function Quote-BashArg {
    param([string]$Value)
    return "'" + ($Value -replace "'", "'""'""'") + "'"
}

$scriptDir = (Resolve-Path (Split-Path -Parent $MyInvocation.MyCommand.Path)).Path

if ($scriptDir -match '^([A-Za-z]):\\(.*)$') {
    $drive = $matches[1].ToLowerInvariant()
    $rest = ($matches[2] -replace '\\', '/')
    $wslDir = "/mnt/$drive/$rest"
} else {
    $wslDir = ""
}

if (-not $wslDir) {
    throw "Unable to translate the picorv32 path into a WSL path."
}

if (-not $ToolchainPrefix) {
    foreach ($prefix in @("riscv32-unknown-elf-", "riscv64-unknown-elf-", "riscv-none-elf-")) {
        $probeCommand = "command -v ${prefix}gcc >/dev/null 2>&1"

        if ($Distro) {
            & wsl -d $Distro bash -lc $probeCommand | Out-Null
        } else {
            & wsl bash -lc $probeCommand | Out-Null
        }

        if ($LASTEXITCODE -eq 0) {
            $ToolchainPrefix = $prefix
            break
        }
    }

    if (-not $ToolchainPrefix) {
        throw "No supported RISC-V toolchain prefix was found in WSL. Pass -ToolchainPrefix explicitly."
    }
}

$bashCommandParts = @(
    "cd $(Quote-BashArg $wslDir)",
    "make $(Quote-BashArg $Target) TOOLCHAIN_PREFIX=$(Quote-BashArg $ToolchainPrefix)"
)

foreach ($arg in $MakeArgs) {
    $bashCommandParts[1] += " $(Quote-BashArg $arg)"
}

$bashCommand = $bashCommandParts -join " && "

if ($Distro) {
    & wsl -d $Distro bash -lc $bashCommand
} else {
    & wsl bash -lc $bashCommand
}

exit $LASTEXITCODE
