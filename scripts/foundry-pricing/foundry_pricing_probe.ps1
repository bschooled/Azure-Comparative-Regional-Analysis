$ErrorActionPreference = "Stop"

$PythonScript = Join-Path $PSScriptRoot "python/foundry_pricing_probe.py"
$ScriptArguments = @($args)

function Test-CompatiblePython {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string[]]$PrefixArguments = @()
    )

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        return $false
    }

    & $Command @PrefixArguments -c "import sys; raise SystemExit(sys.version_info < (3, 10))" 2>$null
    return $LASTEXITCODE -eq 0
}

if (Test-CompatiblePython -Command "py" -PrefixArguments @("-3")) {
    & py -3 $PythonScript @ScriptArguments
    exit $LASTEXITCODE
}
if (Test-CompatiblePython -Command "python3") {
    & python3 $PythonScript @ScriptArguments
    exit $LASTEXITCODE
}
if (Test-CompatiblePython -Command "python") {
    & python $PythonScript @ScriptArguments
    exit $LASTEXITCODE
}

Write-Error "Python 3.10 or newer is required. Install it from https://www.python.org/downloads/."
exit 1
