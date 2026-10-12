param(
    [string]$ResourcePath = 'D:\Github\WORK\NUS\EE2026\EE2026_Project_B-MODs\integration_group_basic_tasks\integration_group_basic_tasks.srcs\sources_1\imports\res',
    [ValidateRange(1, 1000000)][int]$Iterations = 200
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    python export_model.py --weights (Join-Path $ResourcePath 'weights.coe') --image (Join-Path $ResourcePath '00.coe') --out build/generated
    if ($LASTEXITCODE -ne 0) { throw 'Model export failed' }
    gcc -std=c11 -O3 -Wall -Wextra -Werror -Ibuild/generated demo.c neural_net.c -o build/mnist_demo.exe
    if ($LASTEXITCODE -ne 0) { throw 'C compilation failed' }
    gcc -std=c11 -O3 -Wall -Wextra -Werror -shared neural_net.c -o build/neural_net_test.dll
    if ($LASTEXITCODE -ne 0) { throw 'Arithmetic test library compilation failed' }
    python test_arithmetic.py
    if ($LASTEXITCODE -ne 0) { throw 'Arithmetic tests failed' }
    & ./build/mnist_demo.exe $Iterations | Tee-Object -FilePath build/profile.csv
    if ($LASTEXITCODE -ne 0) { throw 'Verification or profiling failed' }
} finally {
    Pop-Location
}
