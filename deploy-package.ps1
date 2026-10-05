# ============================================================
# Wild Papagayo - Deploy Package Builder v2.0
# Builds the full site, validates it, then copies every folder
# a deploy needs into a package folder and zips it.
#
# v2.0 separates three steps that v1.0 ran unconditionally in one
# pass: (1) regenerate + package from a source tree, (2) compile
# Bubu's Cloudflare Function with Wrangler, (3) notify IndexNow.
# Steps 2 and 3 now require explicit opt-in flags, and the source
# tree is a parameter instead of always being this script's own
# folder -- so a clean git worktree/clone can be packaged without
# touching Wrangler or IndexNow at all.
#
# Usage:
#   .\deploy-package.ps1
#       Build/package only, from this script's own folder. No
#       Wrangler, no IndexNow. (Same default scope as before,
#       minus the two side effects.)
#   .\deploy-package.ps1 -SourcePath <clean checkout>
#       Build/package from an explicit source tree instead of the
#       local working copy -- use this to package an exact commit
#       via a clean `git worktree add --detach`.
#   .\deploy-package.ps1 -BuildFunctions
#       Also compile _worker.js/_routes.json with
#       `wrangler pages functions build` (local compile, no
#       network deploy). Required before the package is actually
#       deployable, since Bubu's Function won't work without it.
#   .\deploy-package.ps1 -SubmitIndexNow
#       Also run indexnow-submit.ps1 after packaging. Only run
#       this AFTER the package has actually been deployed live --
#       see indexnow-submit.ps1's own header.
#
# Production deploy itself (`wrangler pages deploy ...`) is still
# a separate, manual step run against the package this script
# produces -- this script never runs it.
# ============================================================

[CmdletBinding()]
param(
    [string]$SourcePath = $PSScriptRoot,
    [string]$PackageDir,
    [string]$PackageZip,
    [switch]$BuildFunctions,
    [switch]$SubmitIndexNow
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path $SourcePath).Path
if (-not $PackageDir) { $PackageDir = Join-Path (Split-Path $root -Parent) 'wild-papagayo-deploy' }
if (-not $PackageZip) { $PackageZip = Join-Path (Split-Path $root -Parent) 'wild-papagayo-deploy.zip' }
$deployDir = $PackageDir
$zipPath = $PackageZip

Write-Host "Source tree: $root" -ForegroundColor DarkGray

Write-Host "== 1/3: Regenerating all content ==" -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'hotel-legacy-publish-all.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'blog-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'hotel-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tour-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'landing-page-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'category-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'hotels-index-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'experience-profile-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'destination-finder-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tool-finder-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'month-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'llms-txt-generator.ps1')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'sitemap-generator.ps1')

Write-Host "== 1b/3: Compiling and validating AI assistant (Bubu) knowledge ==" -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'assistant-knowledge-generator.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host "assistant-knowledge-generator.ps1 failed -- aborting. Bubu's knowledge was not regenerated safely." -ForegroundColor Red
    exit 1
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'assistant-knowledge-validator.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host "assistant-knowledge-validator.ps1 reported FAIL -- aborting. Packaging an empty/corrupt/incomplete assistant knowledge file is not allowed." -ForegroundColor Red
    exit 1
}

Write-Host "== 2/3: Validating content ==" -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'content-link-validator.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host "Validation reported issues -- check reports/content-validation-report.txt before deploying." -ForegroundColor Yellow
}

Write-Host "== 3/3: Building deploy package ==" -ForegroundColor Cyan

# Start from a clean folder every time -- otherwise files removed from source
# (old hero images, deleted hotels/tours, previous unminified JS) silently
# survive as stale copies here forever, since the copy loop below only adds
# and overwrites, never deletes.
if (Test-Path $deployDir) { Remove-Item -Recurse -Force $deployDir }
New-Item -ItemType Directory -Force -Path $deployDir | Out-Null

# Sensitive/internal folders that must never ship, and the file extensions
# that are actually part of the public site.
$excludeDirs = @('.git', 'wild-cms', 'engine', 'knowledge', 'questions', 'reports', 'node_modules', 'docs', 'templates', 'wild-papagayo-deploy', 'tours-backup-before-generator', 'seo-intelligence')
$publicFileExtensions = @('.html', '.xml', '.css', '.ico', '.json', '.js', '.toml', '.txt')
# package.json/package-lock.json must ship -- Netlify's build reads the
# top-level package.json to install the Netlify Function's dependencies
# (@anthropic-ai/sdk). Excluding them (the original behavior) is what caused
# the "Could not resolve @anthropic-ai/sdk" build failure.
$excludeFileNames = @('.env', 'script.src.js', 'WILD-ENGINE-3-README.txt', 'hotel-engine-report.txt', 'knowledge-repository-report.txt', 'question-engine-report.txt')

foreach ($item in Get-ChildItem $root -Force) {
    if ($item.PSIsContainer) {
        if ($excludeDirs -contains $item.Name) { continue }
        Copy-Item $item.FullName -Destination (Join-Path $deployDir $item.Name) -Recurse -Force
    } else {
        if ($excludeFileNames -contains $item.Name) { continue }
        if ($item.Extension -eq '.ps1') { continue }
        $isConfigFile = @('_headers', '_redirects') -contains $item.Name
        if (-not $isConfigFile -and $publicFileExtensions -notcontains $item.Extension) { continue }
        Copy-Item $item.FullName -Destination (Join-Path $deployDir $item.Name) -Force
    }
}

if ($BuildFunctions) {
    Write-Host "== 3b/3: Compiling Bubu's Cloudflare Pages Function (Advanced Mode) ==" -ForegroundColor Cyan
    # wrangler pages deploy is always invoked with --branch in this project's manual
    # deploy flow, and --branch skips Cloudflare's automatic "Pages-to-Workers
    # delegation" that would otherwise compile functions/ for us (proven root cause
    # of the /assistant 404/405 bug, Phase 0X). We compile it ourselves instead and
    # ship it as an explicit _worker.js + _routes.json (Advanced Mode), which
    # Cloudflare always processes regardless of --branch.
    $functionsBuildOut = Join-Path ([System.IO.Path]::GetTempPath()) ("wild-papagayo-functions-build-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $functionsBuildOut | Out-Null
    $routesTempPath = Join-Path $functionsBuildOut '_routes.json'

    & npx wrangler pages functions build (Join-Path $root 'functions') --outdir $functionsBuildOut --output-routes-path $routesTempPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "wrangler pages functions build failed -- aborting. Bubu's /assistant and /health endpoints would not work without this step." -ForegroundColor Red
        Remove-Item -Recurse -Force $functionsBuildOut -ErrorAction SilentlyContinue
        exit 1
    }

    $builtWorker = Get-ChildItem $functionsBuildOut -Filter '*.js' -File | Select-Object -First 1
    if (-not $builtWorker) {
        Write-Host "wrangler pages functions build produced no worker script in $functionsBuildOut -- aborting." -ForegroundColor Red
        Remove-Item -Recurse -Force $functionsBuildOut -ErrorAction SilentlyContinue
        exit 1
    }
    Copy-Item $builtWorker.FullName -Destination (Join-Path $deployDir '_worker.js') -Force

    if (-not (Test-Path $routesTempPath)) {
        Write-Host "wrangler pages functions build produced no _routes.json -- aborting." -ForegroundColor Red
        Remove-Item -Recurse -Force $functionsBuildOut -ErrorAction SilentlyContinue
        exit 1
    }
    Copy-Item $routesTempPath -Destination (Join-Path $deployDir '_routes.json') -Force
    Remove-Item -Recurse -Force $functionsBuildOut -ErrorAction SilentlyContinue

    # Hard validation: if we claim to have built the Function, it must actually
    # be present and complete -- never ship a partial/empty one.
    $workerPath = Join-Path $deployDir '_worker.js'
    $routesPath = Join-Path $deployDir '_routes.json'
    if (-not (Test-Path $workerPath) -or (Get-Item $workerPath).Length -eq 0) {
        Write-Host "_worker.js missing or empty in deploy package -- aborting." -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $routesPath)) {
        Write-Host "_routes.json missing in deploy package -- aborting." -ForegroundColor Red
        exit 1
    }
    $routesJson = Get-Content $routesPath -Raw | ConvertFrom-Json
    $includedRoutes = $routesJson.include
    if (-not ($includedRoutes -contains '/assistant') -or -not ($includedRoutes -contains '/health')) {
        Write-Host "_routes.json does not include both /assistant and /health (found: $($includedRoutes -join ', ')) -- aborting." -ForegroundColor Red
        exit 1
    }
    Write-Host "Bubu Function compiled: _worker.js ($([Math]::Round((Get-Item $workerPath).Length / 1KB, 1)) KB), _routes.json includes /assistant and /health." -ForegroundColor Green
} else {
    Write-Host "== 3b/3: Skipped (pass -BuildFunctions to compile Bubu's Cloudflare Function with Wrangler) ==" -ForegroundColor DarkGray
    Write-Host "This package does NOT include _worker.js/_routes.json and is not yet deployable as-is." -ForegroundColor Yellow
}

# Package source attribution -- written next to the zip, never inside
# $deployDir, so it never ships to production. Lets anyone verify which
# exact commit a given package/zip was built from before deploying it.
$manifestPath = Join-Path (Split-Path $deployDir -Parent) 'wild-papagayo-deploy.manifest.txt'
$sourceCommit = $null
$sourceDirty = $null
try {
    $sourceCommit = (& git -C $root rev-parse HEAD 2>$null)
    $porcelain = (& git -C $root status --porcelain 2>$null)
    $sourceDirty = [bool]$porcelain
} catch { }
$manifestLines = @(
    "Wild Papagayo deploy package manifest"
    "Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Source path: $root"
    "Source commit: $(if ($sourceCommit) { $sourceCommit } else { 'UNKNOWN (source path is not a git repo or git is unavailable)' })"
    "Source working tree dirty: $(if ($null -ne $sourceDirty) { $sourceDirty } else { 'UNKNOWN' })"
    "Functions built (Wrangler): $($BuildFunctions.IsPresent)"
)
$manifestLines | Set-Content -Path $manifestPath -Encoding utf8

Compress-Archive -Path "$deployDir\*" -DestinationPath $zipPath -Force

$sizeMb = [Math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host ""
Write-Host "Deploy package ready: $zipPath ($sizeMb MB)" -ForegroundColor Green
Write-Host "Manifest: $manifestPath" -ForegroundColor Green
Write-Host "Excluded from package: .env, wild-cms/, engine/, knowledge/, questions/, reports/, node_modules/, docs/, templates/, *.ps1" -ForegroundColor DarkGray

if ($SubmitIndexNow) {
    Write-Host ""
    Write-Host "== IndexNow: submitting ($SubmitIndexNow was passed) ==" -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'indexnow-submit.ps1')
} else {
    Write-Host ""
    Write-Host "IndexNow NOT submitted (pass -SubmitIndexNow to notify Bing/Yandex/etc., and only do that after this package has actually been deployed live)." -ForegroundColor DarkGray
}

if (-not $BuildFunctions -or -not $SubmitIndexNow) {
    Write-Host ""
    Write-Host "Next manual steps (NOT run by this script):" -ForegroundColor Cyan
    if (-not $BuildFunctions) {
        Write-Host "  1. Re-run with -BuildFunctions to compile Bubu's Cloudflare Function, OR run:" -ForegroundColor DarkGray
        Write-Host "     npx wrangler pages functions build `"$root\functions`" --outdir <tmp> --output-routes-path <tmp>\_routes.json" -ForegroundColor DarkGray
    }
    Write-Host "  2. Deploy the package (separate, manual, not run by this script):" -ForegroundColor DarkGray
    Write-Host "     npx wrangler pages deploy `"$deployDir`" --project-name=wild-papagayo --branch=<confirm production branch>" -ForegroundColor DarkGray
    if (-not $SubmitIndexNow) {
        Write-Host "  3. Only after that deploy is live, optionally re-run with -SubmitIndexNow, or run indexnow-submit.ps1 directly." -ForegroundColor DarkGray
    }
}
