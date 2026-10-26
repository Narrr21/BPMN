#Requires -Version 5.1
param(
    # Default: file .bpmn di folder yang sama dengan script ini
    [string]$ProcessFile = (Join-Path $PSScriptRoot "order-payment.bpmn"),
    [string]$CamundaDir  = $env:CAMUNDA_DIR,
    [string]$C8ctl       = $env:C8CTL,
    [string]$CamundaUrl  = $(if ($env:CAMUNDA_URL) { $env:CAMUNDA_URL } else { "http://localhost:8080" })
)

$ErrorActionPreference = "Stop"

function Test-Camunda {
    try {
        Invoke-WebRequest -Uri "$CamundaUrl/operate" -UseBasicParsing -TimeoutSec 5 | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# --- Validasi file BPMN ---
if (-not (Test-Path -LiteralPath $ProcessFile -PathType Leaf)) {
    Write-Error "BPMN file not found: $ProcessFile"
    exit 1
}
$ProcessFile = (Resolve-Path -LiteralPath $ProcessFile).Path

# --- Cari c8ctl (dari PATH dulu, baru fallback ke env/parameter) ---
if (-not $C8ctl) {
    $cmd = Get-Command c8ctl -ErrorAction SilentlyContinue
    if ($cmd) { $C8ctl = $cmd.Source }
}
if (-not $C8ctl -or -not (Test-Path -LiteralPath $C8ctl)) {
    Write-Error "c8ctl not found. Install it (npm i -g @camunda8/cli) or set -C8ctl / `$env:C8CTL."
    exit 1
}

# --- Start Camunda kalau belum jalan ---
if (-not (Test-Camunda)) {
    if (-not $CamundaDir) {
        # Cari c8run di lokasi umum: folder script, folder induk, atau C:/
        $candidates = @($PSScriptRoot, (Split-Path $PSScriptRoot -Parent), "C:/") |
            ForEach-Object { Get-ChildItem -Path $_ -Directory -Filter "c8run*" -ErrorAction SilentlyContinue } |
            Where-Object { Test-Path (Join-Path $_.FullName "c8run.exe") } |
            Sort-Object Name -Descending
        if ($candidates) { $CamundaDir = $candidates[0].FullName }
    }

    if (-not $CamundaDir -or -not (Test-Path (Join-Path $CamundaDir "c8run.exe"))) {
        Write-Error "Camunda is not running and c8run.exe was not found. Use -CamundaDir 'C:/path/to/c8run' or set `$env:CAMUNDA_DIR."
        exit 1
    }

    Write-Host "Starting Camunda 8 Run from $CamundaDir..."
    Start-Process `
        -WorkingDirectory $CamundaDir `
        -FilePath (Join-Path $CamundaDir "c8run.exe") `
        -ArgumentList "start", "--no-browser" `
        -WindowStyle Hidden

    Write-Host "Waiting for Camunda..."
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        if (Test-Camunda) { $ready = $true; break }
        Start-Sleep -Seconds 2
    }

    if (-not $ready) {
        Write-Error "Camunda did not become ready at $CamundaUrl."
        exit 1
    }
}

# --- Deploy BPMN ---
Write-Host "Deploying $ProcessFile..."
& $C8ctl deploy $ProcessFile --profile local
if ($LASTEXITCODE -ne 0) { throw "Deploy failed (exit code $LASTEXITCODE)" }

# --- Start process instance ---
Write-Host "Starting process order-payment..."
$variables = '{"orderId":"order-001","amount":500000}'

# Windows PowerShell 5.1 menghilangkan tanda kutip saat memanggil program native,
# jadi perlu di-escape. PowerShell 7.3+ sudah menanganinya sendiri.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $variables = $variables.Replace('"', '\"')
}

& $C8ctl create pi --id=order-payment --profile local --variables $variables
if ($LASTEXITCODE -ne 0) { throw "Create process instance failed (exit code $LASTEXITCODE)" }

Write-Host ""
Write-Host "Process started."
Write-Host "Operate:  $CamundaUrl/operate"
Write-Host "Tasklist: $CamundaUrl/tasklist"