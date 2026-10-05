# ============================================================
# Wild Papagayo - llms.txt Generator v1.0
# Builds llms.txt at the site root -- a plain-text summary for
# AI crawlers/assistants (ChatGPT, Claude, Perplexity, etc.)
# following the llmstxt.org convention. Built from the same real
# knowledge graph as everything else on the site; no invented
# content. Run this after any content change, then redeploy.
# ============================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$siteUrl = "https://wildpapagayo.com"

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Wild Papagayo")
$lines.Add("")
$lines.Add("> Private tour operator and transportation company in Guanacaste and Arenal, Costa Rica -- private day tours, airport transfers and private drivers for travelers who want a personalized, locally-guided trip (not group bus tours).")
$lines.Add("")
$lines.Add("Wild Papagayo is based in Guanacaste, Costa Rica. WhatsApp: +506 8856-6325. Email: info@wildpapagayo.com. All tours and transfers are private and led by ICT-certified local guides.")
$lines.Add("")

# --- Destinations ---
$destDir = Join-Path $root 'knowledge\destinations'
if (Test-Path $destDir) {
    $lines.Add("## Destinations")
    Get-ChildItem $destDir -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
        $d = Read-Utf8Json $_.FullName
        # Strict publication gate: only status "published" is listed.
        if ([string]$d.status -ne 'published') { return }
        $lines.Add("- [$($d.name)]($siteUrl/destinations/$($_.BaseName)): $($d.hero_description)")
    }
    $lines.Add("")
}

# --- Hotels ---
$hotelsDir = Join-Path $root 'knowledge\master\hotels'
if (Test-Path $hotelsDir) {
    $lines.Add("## Hotels")
    Get-ChildItem $hotelsDir -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' } | Sort-Object Name | ForEach-Object {
        $h = Read-Utf8Json $_.FullName
        # Strict eligibility gate -- see assistant-knowledge-generator.ps1 for
        # the reasoning: only an explicit "published" is eligible, not merely
        # "not disabled".
        if ([string]$h.workflow.status -ne 'published') { return }
        $name = if ($h.identity.display_name) { [string]$h.identity.display_name } else { [string]$h.identity.official_name }
        $lines.Add("- [$name]($siteUrl/hotels/$($_.BaseName)): $($h.editorial.hero_description)")
    }
    $lines.Add("")
}

# --- Tours ---
$toursDir = Join-Path $root 'knowledge\tours'
if (Test-Path $toursDir) {
    $lines.Add("## Tours & Experiences")
    Get-ChildItem $toursDir -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
        $t = Read-Utf8Json $_.FullName
        $url = [string]($t.page_url -replace '^\.\./', "$siteUrl/") -replace '\.html$', ''
        $lines.Add("- [$($t.name)]($url): $($t.short_description)")
    }
    $lines.Add("")
}

# --- Travel guides (blog articles) ---
$blogPath = Join-Path $root 'blog-data.json'
if (Test-Path $blogPath) {
    $articles = @(Read-Utf8Json $blogPath)
    if ($articles.Count -gt 0) {
        $lines.Add("## Travel Guides")
        foreach ($a in $articles) {
            $lines.Add("- [$($a.title)]($siteUrl/blog/$($a.slug)): $($a.excerpt)")
        }
        $lines.Add("")
    }
}

# --- Airport transfers (from the same landing-page configs used by
# landing-page-generator.ps1 -- output_dir 'transfers' identifies the
# hotel-specific transfer pages specifically, keeping this section correct
# automatically if more transfer pages are added later, not hardcoded to
# today's two. Reuses each page's own real seo_description -- no new field,
# no superlative language added.) ---
$landingPagesDir = Join-Path $root 'knowledge\landing-pages'
if (Test-Path $landingPagesDir) {
    $transferConfigs = Get-ChildItem $landingPagesDir -Filter '*.json' -File | ForEach-Object {
        $c = Read-Utf8Json $_.FullName
        if ([string]$c.output_dir -eq 'transfers') { $c }
    } | Sort-Object slug
    if ($transferConfigs.Count -gt 0) {
        $lines.Add("## Airport Transfers")
        foreach ($c in $transferConfigs) {
            $lines.Add("- [$($c.h1)]($siteUrl/$($c.output_dir)/$($c.slug)): $($c.seo_description)")
        }
        $lines.Add("")
    }
}

# --- Key pages ---
$lines.Add("## Key Pages")
$lines.Add("- [All Tours]($siteUrl/tours)")
$lines.Add("- [All Hotels]($siteUrl/hotels)")
$lines.Add("- [Multi-Day Journeys]($siteUrl/paquete)")
$lines.Add("- [Private Transportation]($siteUrl/transport)")
$lines.Add("- [Local Guides]($siteUrl/guides)")
$lines.Add("- [Book a Reservation]($siteUrl/Bookingform)")
$lines.Add("- [Travel Insurance]($siteUrl/travel-insurance)")
$lines.Add("- [About Wild Papagayo]($siteUrl/about)")
$lines.Add("- [Contact]($siteUrl/contact)")

$outPath = Join-Path $root 'llms.txt'
[System.IO.File]::WriteAllText($outPath, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Generated llms.txt ($($lines.Count) lines)" -ForegroundColor Green
