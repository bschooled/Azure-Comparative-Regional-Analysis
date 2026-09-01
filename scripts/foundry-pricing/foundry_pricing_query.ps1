$ErrorActionPreference = "Stop"

$PythonScript = Join-Path $PSScriptRoot "python/foundry_pricing_query.py"
$ScriptArguments = @($args)

function Invoke-CompatiblePython {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string[]]$PrefixArguments = @()
    )

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        return $false
    }

    & $Command @PrefixArguments -c "import sys; raise SystemExit(sys.version_info < (3, 10))" 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    & $Command @PrefixArguments $PythonScript @ScriptArguments
    exit $LASTEXITCODE
}

if (Invoke-CompatiblePython -Command "py" -PrefixArguments @("-3")) {
    exit 0
}
if (Invoke-CompatiblePython -Command "python3") {
    exit 0
}
if (Invoke-CompatiblePython -Command "python") {
    exit 0
}

Write-Error "Python 3.10 or newer is required. Install it from https://www.python.org/downloads/."
exit 1
