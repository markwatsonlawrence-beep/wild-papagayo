# ============================================================
# Wild Papagayo - Wild Engine Core v1.0
# Single build command for validation, content generation, logs
# and unified reports.
# Usage: .\wild-engine.ps1
# ============================================================

[CmdletBinding()]
param(
    [switch]$SkipQuestions,
    [switch]$NoHtmlReport
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$configPath = Join-Path $root "engine\config\modules.json"
$reportsDir = Join-Path $root "reports"
$startedAt = Get-Date
$buildStamp = $startedAt.ToString("yyyyMMdd-HHmmss")
$logPath = Join-Path $reportsDir "build-$buildStamp.log"
$textReportPath = Join-Path $reportsDir "build-report.txt"
$htmlReportPath = Join-Path $reportsDir "build-report.html"
$historyPath = Join-Path $reportsDir "build-history.json"

New-Item -ItemType Directory -Force $reportsDir | Out-Null

function Write-EngineLine {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $logPath -Value $Message -Encoding UTF8
}

function Get-PowerShellExecutable {
    $windowsPowerShell = Join-Path $PSHOME "powershell.exe"
    $powerShellCore = Join-Path $PSHOME "pwsh.exe"
    if (Test-Path $windowsPowerShell) { return $windowsPowerShell }
    if (Test-Path $powerShellCore) { return $powerShellCore }
    if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { return "powershell.exe" }
    if (Get-Command pwsh -ErrorAction SilentlyContinue) { return "pwsh" }
    throw "PowerShell executable could not be located."
}

function Invoke-WildModule {
    param(
        [pscustomobject]$Module,
        [int]$Index,
        [int]$Total
    )

    $scriptPath = Join-Path $root ([string]$Module.script)
    $result = [ordered]@{
        id = [string]$Module.id
        name = [string]$Module.name
        script = [string]$Module.script
        required = [bool]$Module.required
        status = "pending"
        exit_code = $null
        duration_seconds = 0
        output = @()
    }

    Write-EngineLine "[$Index/$Total] $($Module.name)..." Cyan

    if (-not (Test-Path $scriptPath)) {
        if ([bool]$Module.required) {
            $result.status = "failed"
            $result.exit_code = 2
            $result.output = @("Missing required module: $($Module.script)")
            Write-EngineLine "  X Missing required module: $($Module.script)" Red
        } else {
            $result.status = "skipped"
            $result.exit_code = 0
            $result.output = @("Optional module is not installed.")
            Write-EngineLine "  - Skipped: module not installed" DarkYellow
        }
        return [pscustomobject]$result
    }

    $moduleStart = Get-Date
    $stdoutPath = Join-Path $env:TEMP "wild-engine-$buildStamp-$($Module.id)-out.txt"
    $stderrPath = Join-Path $env:TEMP "wild-engine-$buildStamp-$($Module.id)-err.txt"
    Remove-Item $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue

    try {
        $executable = Get-PowerShellExecutable
        $arguments = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", ('"{0}"' -f $scriptPath)
        )
        $process = Start-Process -FilePath $executable `
            -ArgumentList $arguments `
            -WorkingDirectory $root `
            -Wait `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $output = New-Object System.Collections.Generic.List[string]
        if (Test-Path $stdoutPath) {
            foreach ($line in (Get-Content $stdoutPath -ErrorAction SilentlyContinue)) {
                if ($null -ne $line -and $line.ToString().Trim().Length -gt 0) {
                    [void]$output.Add($line.ToString())
                }
            }
        }
        if (Test-Path $stderrPath) {
            foreach ($line in (Get-Content $stderrPath -ErrorAction SilentlyContinue)) {
                if ($null -ne $line -and $line.ToString().Trim().Length -gt 0) {
                    [void]$output.Add("ERROR: " + $line.ToString())
                }
            }
        }

        $result.exit_code = $process.ExitCode
        $result.output = @($output)
        if ($process.ExitCode -eq 0) {
            $result.status = "passed"
            Write-EngineLine "  OK Completed" Green
        } else {
            $result.status = "failed"
            Write-EngineLine "  X Failed with exit code $($process.ExitCode)" Red
        }

        foreach ($line in $result.output) {
            Add-Content -Path $logPath -Value ("    " + $line) -Encoding UTF8
        }
    }
    catch {
        $result.status = "failed"
        $result.exit_code = 1
        $result.output = @($_.Exception.Message)
        Write-EngineLine "  X $($_.Exception.Message)" Red
        Add-Content -Path $logPath -Value ("    ERROR: " + $_.Exception.Message) -Encoding UTF8
    }
    finally {
        Remove-Item $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
        $result.duration_seconds = [Math]::Round(((Get-Date) - $moduleStart).TotalSeconds, 2)
    }

    return [pscustomobject]$result
}

function Get-SafeCount {
    param([string]$Path, [string]$Filter = "*")
    if (-not (Test-Path $Path)) { return 0 }
    return @(Get-ChildItem -Path $Path -File -Filter $Filter -ErrorAction SilentlyContinue).Count
}

function Read-JsonCount {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        # NOTE: "@(expr | ConvertFrom-Json).Count" (wrapping a pipeline directly in
        # @()) silently collapses large arrays to Count=1 in Windows PowerShell 5.1.
        # Assign first, then wrap the variable -- that form is safe.
        $parsed = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
        return @($parsed).Count
    } catch {
        return 0
    }
}

function ConvertTo-HtmlSafe {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Value.ToString())
}

if (-not (Test-Path $configPath)) {
    throw "Missing Wild Engine module configuration: $configPath"
}

# Parse first, then enumerate the JSON array.
# Windows PowerShell 5.1 can otherwise treat the whole JSON array as one pipeline item.
$moduleConfig = [System.IO.File]::ReadAllText($configPath) | ConvertFrom-Json
$modules = @(
    $moduleConfig |
    Where-Object { $_.enabled -eq $true } |
    Sort-Object stage
)
if ($SkipQuestions) {
    $modules = @($modules | Where-Object { $_.id -ne "question-engine" })
}

Write-EngineLine "================================================" DarkCyan
Write-EngineLine "             WILD ENGINE CORE v1.1.0" White
Write-EngineLine "================================================" DarkCyan
Write-EngineLine "Build started: $($startedAt.ToString('yyyy-MM-dd HH:mm:ss'))" DarkGray
Write-EngineLine ""

$results = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $modules.Count; $i++) {
    [void]$results.Add((Invoke-WildModule -Module $modules[$i] -Index ($i + 1) -Total $modules.Count))
}

$endedAt = Get-Date
$duration = [Math]::Round(($endedAt - $startedAt).TotalSeconds, 2)
$failed = @($results | Where-Object { $_.status -eq "failed" })
$warnings = 0

# Collect warning counts from existing module reports.
foreach ($reportFile in @("knowledge-repository-report.txt", "question-engine-report.txt", "reports\recommendation-report.txt")) {
    $path = Join-Path $root $reportFile
    if (Test-Path $path) {
        $match = Select-String -Path $path -Pattern '^Warnings:\s*(\d+)' | Select-Object -First 1
        if ($match) { $warnings += [int]$match.Matches[0].Groups[1].Value }
    }
}

$metrics = [ordered]@{
    blogs = Get-SafeCount (Join-Path $root "blog") "*.html"
    destinations = Get-SafeCount (Join-Path $root "destinations") "*.html"
    tours = Get-SafeCount (Join-Path $root "tours") "*.html"
    hotels = Get-SafeCount (Join-Path $root "hotels") "*.html"
    questions = Read-JsonCount (Join-Path $root "questions\questions.json")
}

$status = if ($failed.Count -eq 0) { "successful" } else { "failed" }

$summary = [ordered]@{
    build_id = $buildStamp
    started_at = $startedAt.ToString("o")
    finished_at = $endedAt.ToString("o")
    duration_seconds = $duration
    status = $status
    warnings = $warnings
    errors = $failed.Count
    metrics = $metrics
    modules = $results.ToArray()
}

$text = New-Object System.Collections.Generic.List[string]
[void]$text.Add("Wild Engine Core Build Report")
[void]$text.Add("Build ID: $buildStamp")
[void]$text.Add("Generated: $($endedAt.ToString('yyyy-MM-dd HH:mm:ss'))")
[void]$text.Add("Status: $status")
[void]$text.Add("Duration: $duration seconds")
[void]$text.Add("Warnings: $warnings")
[void]$text.Add("Errors: $($failed.Count)")
[void]$text.Add("")
[void]$text.Add("CONTENT")
[void]$text.Add("Blogs: $($metrics.blogs)")
[void]$text.Add("Destinations: $($metrics.destinations)")
[void]$text.Add("Tours: $($metrics.tours)")
[void]$text.Add("Hotels: $($metrics.hotels)")
[void]$text.Add("Questions: $($metrics.questions)")
[void]$text.Add("")
[void]$text.Add("MODULES")
foreach ($item in $results) {
    [void]$text.Add("- $($item.name): $($item.status) ($($item.duration_seconds)s)")
    if ($item.status -eq "failed") {
        foreach ($line in $item.output) { [void]$text.Add("    $line") }
    }
}
[System.IO.File]::WriteAllLines($textReportPath, [string[]]$text.ToArray(), [System.Text.UTF8Encoding]::new($false))

if (-not $NoHtmlReport) {
    $moduleRows = ($results | ForEach-Object {
        $class = switch ($_.status) {
            "passed" { "ok" }
            "failed" { "bad" }
            default { "skip" }
        }
        "<tr><td>$(ConvertTo-HtmlSafe $_.name)</td><td class='$class'>$(ConvertTo-HtmlSafe $_.status)</td><td>$($_.duration_seconds)s</td></tr>"
    }) -join "`n"
    $statusClass = if ($status -eq "successful") { "ok" } else { "bad" }
    $html = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Wild Engine Build Report</title>
<style>
body{font-family:Arial,sans-serif;background:#f4f6f8;color:#17324d;margin:0;padding:32px}.wrap{max-width:900px;margin:auto}.card{background:#fff;border:1px solid #dfe5ea;border-radius:12px;padding:24px;margin-bottom:18px;box-shadow:0 8px 24px rgba(16,42,67,.06)}h1{margin-top:0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px}.metric{background:#f7f4ee;border-radius:8px;padding:16px}.metric strong{display:block;font-size:28px;color:#062448}.ok{color:#13795b;font-weight:700}.bad{color:#b42318;font-weight:700}.skip{color:#9a6700;font-weight:700}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:12px;border-bottom:1px solid #e6ebef}.meta{color:#64748b;font-size:14px}
</style></head><body><div class="wrap">
<div class="card"><h1>Wild Engine Build</h1><p class="$statusClass">$(ConvertTo-HtmlSafe $status.ToUpperInvariant())</p><p class="meta">Build $buildStamp · $($endedAt.ToString('yyyy-MM-dd HH:mm:ss')) · $duration seconds</p></div>
<div class="card"><h2>Content</h2><div class="grid"><div class="metric"><strong>$($metrics.blogs)</strong>Blogs</div><div class="metric"><strong>$($metrics.destinations)</strong>Destinations</div><div class="metric"><strong>$($metrics.tours)</strong>Tours</div><div class="metric"><strong>$($metrics.hotels)</strong>Hotels</div><div class="metric"><strong>$($metrics.questions)</strong>Questions</div><div class="metric"><strong>$warnings</strong>Warnings</div></div></div>
<div class="card"><h2>Modules</h2><table><thead><tr><th>Module</th><th>Status</th><th>Duration</th></tr></thead><tbody>$moduleRows</tbody></table></div>
</div></body></html>
"@
    [System.IO.File]::WriteAllText($htmlReportPath, $html, [System.Text.UTF8Encoding]::new($false))
}

$history = @()
if (Test-Path $historyPath) {
    try { $history = @(([System.IO.File]::ReadAllText($historyPath) | ConvertFrom-Json)) } catch { $history = @() }
}
$historyEntry = [pscustomobject]@{
    build_id = $buildStamp
    generated_at = $endedAt.ToString("o")
    status = $status
    duration_seconds = $duration
    warnings = $warnings
    errors = $failed.Count
    blogs = $metrics.blogs
    destinations = $metrics.destinations
    tours = $metrics.tours
    hotels = $metrics.hotels
    questions = $metrics.questions
}
$history = @($history + $historyEntry | Select-Object -Last 100)
[System.IO.File]::WriteAllText($historyPath, ($history | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))

Write-EngineLine ""
Write-EngineLine "================================================" DarkCyan
if ($status -eq "successful") {
    Write-EngineLine "BUILD SUCCESSFUL" Green
} else {
    Write-EngineLine "BUILD FAILED" Red
}
Write-EngineLine "Blogs: $($metrics.blogs) | Destinations: $($metrics.destinations) | Tours: $($metrics.tours) | Questions: $($metrics.questions)"
Write-EngineLine "Duration: $duration sec | Warnings: $warnings | Errors: $($failed.Count)"
Write-EngineLine "Report: reports\build-report.html" Cyan
Write-EngineLine "Log: reports\build-$buildStamp.log" DarkGray
Write-EngineLine "================================================" DarkCyan

if ($failed.Count -gt 0) { exit 1 }
exit 0
