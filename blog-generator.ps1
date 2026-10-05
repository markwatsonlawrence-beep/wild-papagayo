# ============================================================
# Wild Papagayo — Static Blog Generator
# Usage: cd to site root, then: .\blog-generator.ps1
# Generates one HTML file per article in /blog/
#
# Optional single-article mode (renders only that article; the FULL dataset is
# still loaded so related cards and Previous/Next are computed correctly):
#     .\blog-generator.ps1 -Slug <article-slug>
# Single-article mode does not run the destination generator and does not touch
# rss.xml unless -RefreshRss is also given. With no parameters the full blog,
# destinations and rss.xml are generated exactly as before.
# ============================================================
[CmdletBinding()]
param(
    [string]$Slug = '',
    [switch]$RefreshRss
)
# NOTE: PowerShell variables are case-insensitive and the article loop assigns $slug, so the
# parameter is copied once here and only $singleSlug is used afterwards.
$singleSlug = $Slug

function Write-FileIfChanged {
    param([string]$Path, [string]$Content)
    if ((Test-Path $Path) -and ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) -ceq $Content)) { return }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

$jsonPath = Join-Path $PSScriptRoot "blog-data.json"
$outDir   = Join-Path $PSScriptRoot "blog"
$siteUrl  = "https://wildpapagayo.com"

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

$articles = [System.IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json

# Deterministic source-order index: slug -> zero-based position in blog-data.json.
# Used ONLY as an explicit secondary sort key. Windows PowerShell 5.1 Sort-Object is
# not stable for tied keys, and how it permutes ties depends on the list length, so
# adding one article used to reshuffle unrelated pages.
$articlePos = @{}
for ($ai = 0; $ai -lt $articles.Count; $ai++) {
    $aslug = [string]$articles[$ai].slug
    if ($articlePos.ContainsKey($aslug)) { throw "Duplicate article slug in blog-data.json: $aslug" }
    $articlePos[$aslug] = $ai
}
if ($singleSlug -and -not $articlePos.ContainsKey($singleSlug)) { throw "-Slug '$singleSlug' is not an article in blog-data.json" }

# Validate every editorial pin up front so a bad pin stops generation before anything is written.
foreach ($va in $articles) {
    $vp = $va.PSObject.Properties['related_slugs']
    if ($vp -and $null -ne $vp.Value) {
        $vs = @($vp.Value)
        if ($vs.Count -eq 0) { throw "related_slugs for '$($va.slug)' is empty" }
        $vseen = @{}
        foreach ($vx in $vs) {
            $vxs = [string]$vx
            if ($vxs -eq [string]$va.slug) { throw "related_slugs for '$($va.slug)' contains the article itself" }
            if (-not $articlePos.ContainsKey($vxs)) { throw "related_slugs for '$($va.slug)' references unknown slug '$vxs'" }
            if ($vseen.ContainsKey($vxs)) { throw "related_slugs for '$($va.slug)' repeats '$vxs'" }
            $vseen[$vxs] = $true
        }
    }
}

# ── Decision Engine: tours available for "Recommended For Your Trip" matching ──
$toursDir = Join-Path $PSScriptRoot 'knowledge\tours'
$toursForRec = @()
if (Test-Path $toursDir) {
    $toursForRec = Get-ChildItem $toursDir -Filter '*.json' -File | ForEach-Object {
        $t = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        [pscustomobject]@{
            id = [string]$t.id
            name = [string]$t.name
            category = [string]$t.category
            best_for = @($t.best_for)
            destination_ids = @($t.destination_ids)
            image = [string]$t.hero_image
            description = [string]$t.short_description
            url = [string]$t.page_url
            difficulty = [string]$t.difficulty
            minimum_age = [int]$t.minimum_age
        }
    }
}
# Validate every recommended_tour_ids pin up front; a bad pin stops generation before anything is written
# and never falls back to the algorithm.
foreach ($vt in $articles) {
    $vtp = $vt.PSObject.Properties['recommended_tour_ids']
    if ($vtp -and $null -ne $vtp.Value) {
        $vtids = @($vtp.Value)
        if ($vtids.Count -eq 0) { throw "recommended_tour_ids for '$($vt.slug)' is empty" }
        $vtseen = @{}
        foreach ($vtid in $vtids) {
            $vtidS = [string]$vtid
            if ($vtseen.ContainsKey($vtidS)) { throw "recommended_tour_ids for '$($vt.slug)' repeats '$vtidS'" }
            $vtseen[$vtidS] = $true
            $vtour = @($toursForRec | Where-Object { $_.id -eq $vtidS })
            if ($vtour.Count -ne 1) { throw "recommended_tour_ids for '$($vt.slug)' references unknown tour id '$vtidS'" }
            if ([string]::IsNullOrWhiteSpace($vtour[0].url) -or [string]::IsNullOrWhiteSpace($vtour[0].name) -or [string]::IsNullOrWhiteSpace($vtour[0].image)) { throw "recommended_tour_ids for '$($vt.slug)': tour '$vtidS' cannot be rendered as a card" }
            $vtPage = Join-Path $PSScriptRoot ('tours\' + (([string]$vtour[0].url) -replace '^\.\./tours/', '') + '.html')
            if (-not (Test-Path $vtPage)) { throw "recommended_tour_ids for '$($vt.slug)': public page for tour '$vtidS' not found ($vtPage)" }
        }
    }
}
function Get-WildWordSet {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @(($Text.ToLowerInvariant() -split '[^a-z]+') | Where-Object { $_ })
}

# ── Dynamic CTA: name lookups for hotels/seasons, reused per-article below ──
$hotelsDirForCta = Join-Path $PSScriptRoot 'knowledge\master\hotels'
$hotelNameById = @{}
if (Test-Path $hotelsDirForCta) {
    Get-ChildItem $hotelsDirForCta -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' } | ForEach-Object {
        $h = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $name = if ($h.identity.display_name) { [string]$h.identity.display_name } else { [string]$h.identity.official_name }
        $hotelNameById[$_.BaseName] = $name
    }
}
$monthDisplayById = @{
    january='January'; february='February'; march='March'; april='April'; may='May'; june='June'
    july='July'; august='August'; september='September'; october='October'; november='November'; december='December'
    'dry-season'='Dry Season'; 'green-season'='Green Season'
}

# HTML template — single-quoted here-string: NO variable expansion, all subs via .Replace()
$template = @'
<!DOCTYPE html>
<html lang="en" data-slug="__SLUG__">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>__PAGE_TITLE__</title>
  <meta name="description" content="__SEO_DESC__">
  <meta name="keywords" content="__SEO_KEYWORDS__">
  <meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1">
  <meta name="author" content="__AUTHOR_NAME__">
  <meta name="publisher" content="Wild Papagayo">
  <meta name="theme-color" content="#062448">
  <link rel="canonical" href="__CANONICAL_URL__">

  <meta property="og:site_name" content="Wild Papagayo">
  <meta property="og:locale" content="en_CR">
  <meta property="og:type" content="article">
  <meta property="og:title" content="__PAGE_TITLE__">
  <meta property="og:description" content="__SEO_DESC__">
  <meta property="og:image" content="__OG_IMAGE__">
  <meta property="og:image:alt" content="__OG_IMAGE_ALT__">
  <meta property="og:url" content="__CANONICAL_URL__">
  <meta property="article:author" content="__AUTHOR_NAME__">
  <meta property="article:publisher" content="Wild Papagayo">
  <meta property="article:section" content="__CATEGORY__">
  <meta property="article:published_time" content="__ISO_DATE__">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="__PAGE_TITLE__">
  <meta name="twitter:description" content="__SEO_DESC__">
  <meta name="twitter:image" content="__OG_IMAGE__">
  <meta name="twitter:image:alt" content="__OG_IMAGE_ALT__">

  <link rel="stylesheet" href="../style.min.css">
  <link rel="icon" type="image/png" sizes="512x512" href="../images/favicon-wildpapagayo.png"><link rel="icon" type="image/svg+xml" href="../images/favicon-wildpapagayo.svg">

  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"TravelAgency","@id":"https://wildpapagayo.com/#organization","name":"Wild Papagayo","url":"https://wildpapagayo.com/","telephone":"+50688566325","email":"info@wildpapagayo.com","priceRange":"$$$","image":"https://wildpapagayo.com/images/logo-wildpapagayo-nav.webp","description":"Private Costa Rica tours, airport transfers and local guide services.","areaServed":{"@type":"Country","name":"Costa Rica"},"address":{"@type":"PostalAddress","addressLocality":"Guanacaste","addressRegion":"Guanacaste","addressCountry":"CR"},"sameAs":["https://facebook.com/share/1JLByXiV4k/?mibextid=wwXIfr","https://instagram.com/wild.papagayo"]}
  </script>
  <script type="application/ld+json">__SCHEMA_ARTICLE__</script>
  <script type="application/ld+json">__SCHEMA_BREADCRUMB__</script>
  __SCHEMA_FAQ__

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Plus+Jakarta+Sans:wght@400;800;900&display=swap" media="print" onload="this.media='all'">
  <noscript><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Plus+Jakarta+Sans:wght@400;800;900&display=swap"></noscript>

  <style>
  :root{--b-navy:#062448;--b-navy-soft:#0d3a6e;--b-gold:#C9A24B;--b-cream:#F7F4EE;--b-grey:#5A5A5A;--b-line:#E4DFD4;--b-blue:#EEF6FF;}
  /* ── HERO ── */
  .blog-topbar{background:var(--b-navy);color:#fff;text-align:center;font-size:12.5px;letter-spacing:.03em;padding:9px 16px;}
  .blog-topbar a{color:var(--b-gold);text-decoration:none;font-weight:700;}
  .blog-topbar a:hover{text-decoration:underline;}
  .blog-header-plain{background:var(--b-cream);padding:52px 0 0;text-align:center;}
  .blog-hero-inner{width:min(92%,760px);margin:0 auto;padding:0 0 36px;}
  .blog-eyebrow{font-size:11.5px;letter-spacing:.18em;text-transform:uppercase;color:var(--b-gold);margin-bottom:14px;font-weight:700;}
  .blog-breadcrumb{font-size:.78rem;color:var(--b-grey);margin-bottom:16px;display:flex;align-items:center;justify-content:center;gap:6px;flex-wrap:wrap;}
  .blog-breadcrumb a{color:var(--b-grey);text-decoration:none;}
  .blog-breadcrumb a:hover{color:var(--b-navy);text-decoration:underline;}
  .blog-breadcrumb span{color:#8a6e24;font-weight:700;}
  .blog-hero-inner h1{font-family:'Cormorant Garamond',Georgia,serif;font-size:clamp(2rem,5vw,3.2rem);font-weight:600;line-height:1.12;margin:0 0 20px;color:var(--b-navy);}
  .blog-meta{font-size:12.5px;display:flex;gap:10px;flex-wrap:wrap;align-items:center;justify-content:center;}
  .blog-meta-date{color:var(--b-grey);}
  .blog-meta-sep{color:var(--b-line);}
  .blog-meta-read{color:#8a6e24;font-weight:700;}
  .blog-meta .blog-author-name{color:var(--b-grey);font-weight:600;letter-spacing:.02em;}
  .blog-hero-photo{width:min(92%,900px);aspect-ratio:16/9;margin:0 auto;border-radius:10px;overflow:hidden;background:#e4dfd4;}
  .blog-hero-photo img{width:100%;height:100%;object-fit:cover;display:block;}
  @media(max-width:600px){.blog-hero-photo{aspect-ratio:4/3;border-radius:6px;}}
  /* ── ARTICLE ── */
  .blog-article-wrap{max-width:720px;margin:0 auto;padding:0 24px 60px;}
  /* ── EXCERPT: large centered serif, no border (Aman style) ── */
  .blog-excerpt{font-family:'Cormorant Garamond',Georgia,serif;font-style:italic;font-size:clamp(1.35rem,3vw,1.85rem);color:var(--b-navy);text-align:center;margin:56px auto 44px;max-width:560px;line-height:1.52;font-weight:500;display:block;}
  /* ── QUICK FACTS / PACKING LIST ── */
  .blog-facts-box{background:var(--b-cream);border:1px solid var(--b-line);border-radius:4px;padding:22px 28px;margin:32px 0;}
  .blog-facts-title{font-size:10.5px;font-weight:800;letter-spacing:.18em;text-transform:uppercase;color:var(--b-navy);margin-bottom:14px;}
  .blog-facts-list{list-style:none;padding:0;margin:0;display:grid;grid-template-columns:1fr 1fr;gap:10px 24px;}
  .blog-facts-list li{font-size:14px;color:var(--b-grey);padding-left:20px;position:relative;margin:0;line-height:1.5;}
  .blog-facts-list li::before{content:"\2713";position:absolute;left:0;color:#8a6e24;font-weight:800;}
  /* ── BEST FOR ── */
  .blog-best-for{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:0 0 36px;}
  .blog-best-for-label{font-size:10.5px;font-weight:800;letter-spacing:.14em;text-transform:uppercase;color:var(--b-grey);margin-right:4px;}
  .blog-best-for-tag{display:inline-block;padding:5px 14px;border-radius:999px;border:1.5px solid var(--b-line);font-size:12px;color:var(--b-navy);font-weight:600;}
  /* ── RECOMMENDED FOR YOUR TRIP (Decision Engine) ── */
  .blog-decision-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:24px 0 32px;}
  .blog-decision-card{background:#fff;border:1px solid var(--b-line);border-radius:6px;padding:16px 18px;}
  .blog-decision-label{display:block;font-size:10.5px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;color:var(--b-gold);margin-bottom:6px;}
  .blog-decision-card p{margin:0;font-size:14px;line-height:1.5;color:var(--b-navy);}
  .blog-decision-card a{color:var(--b-green);font-weight:700;text-decoration:underline;text-decoration-color:rgba(13,122,95,.35);}
  @media(max-width:600px){.blog-decision-grid{grid-template-columns:1fr;}}
  .blog-recommended{background:var(--b-cream);border-radius:6px;padding:32px 28px;margin:40px 0;}
  .blog-recommended h2{font-family:Georgia,serif;color:var(--b-navy);font-size:1.35rem;margin:0 0 18px;}
  .blog-rec-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;}
  .blog-rec-card{display:flex!important;flex-direction:column!important;background:#fff;border:1px solid var(--b-line);border-radius:6px;overflow:hidden;text-decoration:none!important;color:inherit!important;transition:transform .2s ease,box-shadow .2s ease;}
  .blog-rec-card:hover{transform:translateY(-3px);box-shadow:0 10px 26px rgba(6,36,72,.12);}
  .blog-rec-card img{width:100%;height:140px;object-fit:cover;display:block;}
  .blog-rec-card-body{padding:14px 16px;}
  .blog-rec-card-body span{color:var(--b-gold);font-size:10px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;}
  .blog-rec-card-body h3{font-family:Georgia,serif;color:var(--b-navy);font-size:1rem;margin:6px 0 6px;}
  .blog-rec-card-body p{color:var(--b-grey);font-size:12.5px;line-height:1.5;margin:0;}
  @media(max-width:700px){.blog-rec-grid{grid-template-columns:1fr;}}
  /* ── BODY ── */
  .blog-body{font-size:16.5px;color:#3a3a3a;line-height:1.78;}
  .blog-body p{margin:0 0 22px;}
  .blog-body h2{font-family:'Cormorant Garamond',Georgia,serif;font-size:clamp(1.5rem,3.5vw,1.9rem);font-weight:600;color:var(--b-navy);margin:48px 0 16px;position:relative;padding-bottom:12px;}
  .blog-body h2::after{content:"";position:absolute;left:0;bottom:0;width:44px;height:2px;background:var(--b-gold);}
  .blog-body h2.h2-plain{padding-bottom:0;}
  .blog-body h2.h2-plain::after{display:none;}
  .blog-body h3{font-family:'Cormorant Garamond',Georgia,serif;font-size:1.25rem;font-weight:600;color:var(--b-navy-soft);margin:28px 0 8px;}
  .blog-body ul,.blog-body ol{padding-left:22px;margin:0 0 22px;}
  .blog-body li{margin-bottom:8px;}
  .blog-body a:not(.blog-cta-button){color:#0d7a5f;font-weight:700;text-decoration:underline;text-decoration-color:rgba(13,122,95,.35);text-underline-offset:3px;transition:color .18s;}
  .blog-body a:not(.blog-cta-button):hover{color:#095c47;}
  .blog-body blockquote{background:var(--b-cream);border-left:3px solid var(--b-gold);padding:22px 26px;margin:32px 0;border-radius:2px;}
  .blog-body blockquote p{margin:0;font-size:15.5px;color:var(--b-grey);}
  .blog-body blockquote strong:first-child{display:block;font-size:11.5px;letter-spacing:.08em;text-transform:uppercase;color:var(--b-navy);margin-bottom:10px;}
  /* ── TRAVEL TIP ── */
  .blog-tip-box{background:var(--b-gold);padding:22px 28px;margin:36px 0;border-radius:4px;}
  .blog-tip-label{font-size:10.5px;font-weight:800;letter-spacing:.18em;text-transform:uppercase;color:var(--b-navy);margin-bottom:10px;}
  .blog-tip-box p{color:var(--b-navy);font-size:15px;margin:0;line-height:1.65;font-weight:500;}
  /* ── DID YOU KNOW ── */
  .blog-dyk-box{background:var(--b-blue);border-left:3px solid #0b67a3;padding:20px 26px;margin:32px 0;border-radius:2px;}
  .blog-dyk-label{font-size:10.5px;font-weight:800;letter-spacing:.18em;text-transform:uppercase;color:#0b67a3;margin-bottom:8px;}
  .blog-dyk-box p{font-size:15px;color:var(--b-navy);margin:0;line-height:1.65;}
  /* ── INTERNAL LINKS ── */
  .blog-related-links{margin:42px 0;padding:28px;background:var(--b-cream);border:1px solid var(--b-line);border-radius:4px;}
  .blog-related-links-title{font-family:'Cormorant Garamond',Georgia,serif;font-size:1.45rem;font-weight:600;color:var(--b-navy);margin:0 0 18px;}
  .blog-related-links-list{list-style:none;padding:0 !important;margin:0 !important;display:grid;gap:10px;}
  .blog-related-links-list li{margin:0;}
  .blog-related-links-list a{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:13px 16px;background:#fff;border:1px solid var(--b-line);border-radius:3px;color:var(--b-navy) !important;text-decoration:none !important;font-size:14px;font-weight:700;transition:transform .18s ease,border-color .18s ease;}
  .blog-related-links-list a::after{content:"\2192";color:var(--b-gold);font-size:18px;flex-shrink:0;}
  .blog-related-links-list a:hover{transform:translateX(3px);border-color:var(--b-gold);}
  /* ── FAQ ── */
  .blog-faq h2{font-family:'Cormorant Garamond',Georgia,serif;font-size:clamp(1.5rem,3.5vw,1.9rem);font-weight:600;color:var(--b-navy);margin:48px 0 16px;position:relative;padding-bottom:12px;}
  .blog-faq h2::after{content:"";position:absolute;left:0;bottom:0;width:44px;height:2px;background:var(--b-gold);}
  .blog-faq h3{font-family:'Cormorant Garamond',Georgia,serif;font-size:1.2rem;font-weight:600;color:var(--b-navy-soft);margin:24px 0 6px;}
  .blog-faq p{font-size:15.5px;color:#3a3a3a;line-height:1.7;margin:0 0 16px;}
  /* ── FIGURES ── */
  .blog-figure{margin:36px 0;}
  .blog-figure img{width:100%;height:auto;display:block;border-radius:3px;}
  .blog-figure figcaption{font-size:12px;color:#8a8a8a;margin-top:8px;text-align:center;font-style:italic;}
  /* ── AUTHOR BOX ── */
  .blog-author-box{display:flex;align-items:center;gap:14px;border-top:1px solid var(--b-line);border-bottom:1px solid var(--b-line);padding:20px 0;margin:40px 0;}
  .blog-author-avatar{width:46px;height:46px;border-radius:50%;overflow:hidden;flex-shrink:0;background:var(--b-navy);}
  .blog-author-avatar img{width:100%;height:100%;object-fit:cover;display:block;}
  .blog-author-name-text{font-weight:700;font-size:14px;color:var(--b-navy);}
  .blog-author-badge-text{font-size:12px;color:var(--b-grey);margin-top:2px;}
  /* ── SHARE ── */
  .blog-share{border-top:1px solid var(--b-line);padding-top:28px;margin-top:8px;}
  .blog-share-label{font-size:.72rem;font-weight:700;text-transform:uppercase;letter-spacing:.1em;color:#667085;margin:0 0 14px;}
  .blog-share-row{display:flex;gap:10px;flex-wrap:wrap;align-items:center;}
  /* ── CTA ── */
  .blog-cta-block{background:var(--b-navy);color:#fff;text-align:center;border-radius:4px;padding:44px 32px;margin:48px 0 32px;}
  .blog-cta-block .blog-eyebrow{color:var(--b-gold);margin-bottom:10px;}
  .blog-cta-block h3{font-family:'Cormorant Garamond',Georgia,serif;font-size:clamp(1.4rem,3vw,1.9rem);margin:0 0 10px;color:#fff;font-weight:600;}
  .blog-cta-block p{color:rgba(255,255,255,.70);margin:0 0 24px;font-size:15px;max-width:480px;margin-left:auto;margin-right:auto;}
  .blog-cta-button{display:inline-block;background:var(--b-gold);color:var(--b-navy) !important;font-weight:700;font-size:13.5px;letter-spacing:.03em;text-decoration:none !important;padding:14px 32px;border-radius:2px;transition:opacity .2s;}
  .blog-cta-button:hover{opacity:.88;}
  .blog-cta-actions{display:flex;gap:14px;justify-content:center;flex-wrap:wrap;}
  .blog-cta-button-alt{display:inline-block;background:transparent;border:1.5px solid rgba(255,255,255,.55);color:#fff !important;font-weight:700;font-size:13.5px;letter-spacing:.03em;text-decoration:none !important;padding:12.5px 32px;border-radius:2px;transition:.2s;}
  .blog-cta-button-alt:hover{background:rgba(255,255,255,.1);border-color:#fff;}
  .blog-cta-email-link{display:block;margin-top:18px;font-size:12.5px;color:rgba(255,255,255,.55);text-decoration:underline;}
  .blog-cta-email-link:hover{color:var(--b-gold);}
  .blog-newsletter-block{background:var(--b-cream);border:1px solid var(--b-line);border-radius:4px;padding:40px 32px;margin:0 0 32px;text-align:center;}
  .blog-newsletter-block .blog-eyebrow{margin-bottom:10px;}
  .blog-newsletter-block h3{font-family:'Cormorant Garamond',Georgia,serif;font-size:clamp(1.3rem,2.8vw,1.7rem);margin:0 0 10px;color:var(--b-navy);font-weight:600;}
  .blog-newsletter-block p{color:var(--b-grey);margin:0 0 22px;font-size:14.5px;max-width:440px;margin-left:auto;margin-right:auto;}
  .blog-newsletter-block .newsletter-form{max-width:420px;margin:0 auto;flex-direction:row;gap:8px;align-items:center;}
  .blog-newsletter-block .newsletter-form input[type="email"]{border:1px solid var(--b-line) !important;background:#fff !important;color:var(--b-navy) !important;text-align:left !important;flex:1;}
  .blog-newsletter-block .newsletter-form input[type="email"]::placeholder{color:#98a2b3;text-align:left !important;}
  .blog-newsletter-block .btn-newsletter{width:auto !important;padding:14px 22px !important;}
  @media(max-width:600px){
    .blog-newsletter-block{padding:28px 20px;}
    .blog-newsletter-block .newsletter-form{flex-direction:column;}
    .blog-newsletter-block .btn-newsletter{width:100% !important;}
  }
  @media(max-width:600px){
    .blog-hero-inner h1{font-size:1.8rem;}
    .blog-body h2,.blog-faq h2{font-size:1.35rem;}
    .blog-excerpt{font-size:1.2rem;margin:40px auto 32px;}
    .blog-article-wrap{padding:0 16px 48px;}
    .blog-cta-block{padding:32px 20px;}
    .blog-facts-list{grid-template-columns:1fr;}
    .blog-related-links{padding:20px;margin:34px 0;}
    .blog-related-links-title{font-size:1.25rem;}
    .blog-related-links-list a{padding:12px 14px;}
  }
  .blog-toc{background:#f8f5ef;border:1px solid #e5ded1;border-radius:10px;padding:20px 24px;margin:28px 0}
  .blog-toc-title{font-weight:800;color:#062448;font-size:.85rem;letter-spacing:.06em;text-transform:uppercase;margin:0 0 10px}
  .blog-toc ol{margin:0;padding-left:20px}
  .blog-toc li{margin:6px 0}
  .blog-toc a{color:#0d3a6e;text-decoration:none;font-weight:600}
  .blog-toc a:hover{text-decoration:underline}
  .blog-related-articles{margin:44px 0}
  .blog-related-articles-title{font-family:'Cormorant Garamond',Georgia,serif;color:#062448;font-size:1.6rem;margin:0 0 16px}
  .blog-related-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}
  .blog-related-card{display:block;background:#fff;border:1px solid #e5ded1;border-radius:9px;overflow:hidden;text-decoration:none!important;color:inherit!important;box-shadow:0 8px 22px rgba(6,36,72,.06)}
  .blog-related-card img{width:100%;height:140px;object-fit:cover;display:block}
  .blog-related-card div{padding:14px 16px}
  .blog-related-card small{color:#8a6e24;font-size:.65rem;font-weight:800;letter-spacing:.08em;text-transform:uppercase}
  .blog-related-card h4{font-family:'Cormorant Garamond',Georgia,serif;color:#062448;font-size:1.15rem;margin:6px 0 0;line-height:1.25}
  .blog-prevnext{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:36px 0}
  .blog-prevnext a{display:block;padding:16px 18px;border:1px solid #e5ded1;border-radius:9px;text-decoration:none!important;color:inherit!important;background:#fff}
  .blog-prevnext small{color:#667085;font-size:.68rem;letter-spacing:.08em;text-transform:uppercase;font-weight:800}
  .blog-prevnext strong{display:block;margin-top:4px;color:#062448;font-family:'Cormorant Garamond',Georgia,serif;font-size:1.1rem}
  .blog-prevnext .blog-next{text-align:right}
  .blog-updated{color:#667085;font-size:.8rem;margin:0 0 10px}
  @media(max-width:700px){.blog-related-grid{grid-template-columns:1fr}.blog-prevnext{grid-template-columns:1fr}}
  </style>

<!-- Google tag (gtag.js) -- deferred until window 'load' so it never competes with LCP/FCP-critical resources -->
<script>
window.addEventListener('load', function() {
  var s = document.createElement('script');
  s.async = true;
  s.src = 'https://www.googletagmanager.com/gtag/js?id=G-9V2MY7J6RJ';
  document.head.appendChild(s);
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  window.gtag = gtag;
  gtag('js', new Date());
  gtag('config', 'G-9V2MY7J6RJ');
});
</script>
</head>
<body>
  <a href="#main-content" style="position:absolute;left:-999px;top:auto;width:1px;height:1px;overflow:hidden;">Skip to main content</a>

  <header class="site-header">
    <nav class="nav container" aria-label="Main navigation">
      <a class="brand" href="../" aria-label="Wild Papagayo home">
        <img alt="Wild Papagayo" src="../images/logo-wildpapagayo-nav.webp" width="160" height="80" decoding="async" loading="eager">
      </a>
      <button type="button" aria-label="Open menu" aria-expanded="false" aria-controls="main-navigation" class="hamburger">&#9776;</button>
      <div class="nav-links" id="main-navigation">
        <a href="../">Home</a>
        <a href="../tours">All Experiences</a>
        <a href="../paquete">Multi-Day Journeys</a>
        <div class="nav-dropdown">
          <button class="nav-dropdown-trigger" aria-expanded="false" aria-haspopup="true">Discover <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg></button>
          <div class="nav-dropdown-menu">
            <a href="../destination-finder">Destinations</a>
            <a href="../hotels">Hotels</a>
            <a href="../private-tours/peninsula-papagayo">Tours from Papagayo</a>
            <a href="../months">When to Visit</a>
            <a href="liberia-airport-transfer-guide">Liberia Airport Guide</a>
            <a href="../waterfalls-near-papagayo-guide">Waterfalls Near Papagayo</a>
            <a href="../plan-by-traveler-type">Plan by Traveler Type</a>
          </div>
        </div>
        <a href="../transport">Transport</a>
        <a href="../guides">Expert Guides</a>
        <a href="../about">Our Story</a>
        <a href="../Blogs" aria-current="page">Insider Guide</a>
        <a href="../travel-insurance">Travel Insurance</a>
        <a href="../contact">Connect</a>
      </div>
      <a class="btn btn-primary header-cta" href="https://wa.me/50688566325?text=Hello%20Wild%20Papagayo!%20I%20want%20to%20plan%20my%20Costa%20Rica%20trip." target="_blank" rel="noopener noreferrer">Plan Your Trip</a>
    </nav>
  </header>

  <div class="blog-topbar">WILD PAPAGAYO &middot; GUANACASTE, COSTA RICA &nbsp;&mdash;&nbsp; <a href="https://wa.me/50688566325?text=Hello%20Wild%20Papagayo!%20I%27d%20love%20help%20planning%20my%20Costa%20Rica%20trip.">Plan My Journey &rarr;</a></div>

  <header class="blog-header-plain">
    <div class="blog-hero-inner">
      <nav class="blog-breadcrumb" aria-label="Breadcrumb"><a href="../">Home</a>&rsaquo;<a href="../Blogs">Insider Guide</a>&rsaquo;<span>__CATEGORY__</span></nav>
      <h1>__TITLE__</h1>
      <div class="blog-meta">
        <span class="blog-meta-date">__DATE__</span>
        __READ_TIME__
        <span class="blog-meta-sep">&middot;</span>
        <span class="blog-author-name">__AUTHOR_NAME__</span>
      </div>
    </div>
    <div class="blog-hero-photo"><img src="../__HERO_IMAGE__" alt="__OG_IMAGE_ALT__" width="1600" height="900" loading="eager" fetchpriority="high" decoding="async"></div>
  </header>

  <main id="main-content">
    <div class="blog-article-wrap">
      <p class="blog-updated">__LAST_UPDATED__</p>
      <p class="blog-excerpt">__EXCERPT__</p>
      __QUICK_FACTS__
      __BEST_FOR__
      __RECOMMENDED_FOR_TRIP__
      __INTERNAL_LINKS__
      __TABLE_OF_CONTENTS__
      <div class="blog-body">
        __ARTICLE_BODY__
        __PACKING_LIST__
        __DID_YOU_KNOW__
        __BOTTOM_IMG__
        <section>__CONTENT_3__</section>
        __FAQ_BLOCK__
        __RELATED_ARTICLES__
        __PREV_NEXT_NAV__
        <div class="blog-author-box">
          <div class="blog-author-avatar">
            <img src="../images/favicon-wildpapagayo.svg" alt="Wild Papagayo" width="46" height="46">
          </div>
          <div>
            <div class="blog-author-name-text">__AUTHOR_NAME__</div>
            <div class="blog-author-badge-text">__AUTHOR_BADGE__</div>
          </div>
        </div>
        <div class="blog-share">
          <p class="blog-share-label">Share this article</p>
          <div class="blog-share-row">
            <a href="__WA_SHARE__" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:8px;background:#0d7a3a;color:#fff;font-weight:700;font-size:.86rem;padding:10px 20px;border-radius:50px;text-decoration:none;">
              <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="#fff"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413z"/></svg>
              WhatsApp
            </a>
            <a href="__FB_SHARE__" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:8px;background:#0d5bc4;color:#fff;font-weight:700;font-size:.86rem;padding:10px 20px;border-radius:50px;text-decoration:none;">
              <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="#fff"><path d="M18 2h-3a5 5 0 0 0-5 5v3H7v4h3v8h4v-8h3l1-4h-4V7a1 1 0 0 1 1-1h3z"/></svg>
              Facebook
            </a>
            <button onclick="navigator.clipboard.writeText(location.href).then(function(){var b=document.getElementById('copyBtn');b.textContent='\u2713 Copied';setTimeout(function(){b.textContent='Copy Link'},2000)})" id="copyBtn" style="display:inline-flex;align-items:center;gap:8px;background:#f0f0f0;color:#3a3a3a;font-weight:700;font-size:.86rem;padding:10px 20px;border-radius:50px;border:none;cursor:pointer;">
              <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>
              Copy Link
            </button>
            <a href="../Blogs" style="display:inline-flex;align-items:center;gap:6px;color:#667085;font-size:.86rem;font-weight:600;text-decoration:none;padding:10px 14px;">&larr; More articles</a>
          </div>
        </div>
        <div class="blog-cta-block">
          <div class="blog-eyebrow">Need Help Planning?</div>
          <h3>We respond on WhatsApp in under 2 hours.</h3>
          <p>Private tours, airport transfers, expert guides &mdash; all in one message.</p>
          <div class="blog-cta-actions">
            <a class="blog-cta-button" data-intent="__CTA_INTENT__" data-cta-location="blog_main" href="__CTA_URL__">__CTA_TEXT__ &rarr;</a>
            <a class="blog-cta-button-alt" href="../Bookingform">Request a Reservation &rarr;</a>
          </div>
          <a class="blog-cta-email-link" href="mailto:info@wildpapagayo.com?subject=Costa%20Rica%20Trip%20Inquiry">No WhatsApp? Email us at info@wildpapagayo.com</a>
        </div>
        <div class="blog-newsletter-block">
          <div class="blog-eyebrow">Not Ready to Book Yet?</div>
          <h3>Get Costa Rica trip tips before you go.</h3>
          <p>Seasonal advice, new tours and honest planning tips from our local team, sent straight to your inbox.</p>
          <div class="newsletter-form">
            <label for="blogNewsletterEmail" class="sr-only">Email</label>
            <input id="blogNewsletterEmail" name="blogNewsletterEmail" type="email" placeholder="Your email address" required>
            <button class="btn-newsletter" type="button" id="btnBlogNewsletter" onclick="enviarNewsletter('blogNewsletterEmail','btnBlogNewsletter')">Send Me Tips</button>
          </div>
        </div>
      </div>
    </div>
  </main>

  <footer class="footer">
    <div class="container footer-grid footer-grid-clean">
      <div class="footer-brand">
        <img src="../images/logo-wildpapagayo-nav.webp" alt="Wild Papagayo" class="footer-logo" width="180" height="180">
        <p>Exceptional Costa Rica, exclusively curated for discerning travelers.</p>
        <div class="footer-social">
          <a href="https://www.instagram.com/wild.papagayo" target="_blank" rel="noopener noreferrer" aria-label="Instagram" class="footer-social-ig"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="2" width="20" height="20" rx="5" ry="5"/><path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z"/><line x1="17.5" y1="6.5" x2="17.51" y2="6.5"/></svg></a>
          <a href="https://www.facebook.com/share/1JLByXiV4k/?mibextid=wwXIfr" target="_blank" rel="noopener noreferrer" aria-label="Facebook" class="footer-social-fb"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 2h-3a5 5 0 0 0-5 5v3H7v4h3v8h4v-8h3l1-4h-4V7a1 1 0 0 1 1-1h3z"/></svg></a>
          <a href="https://wa.me/50688566325" target="_blank" rel="noopener noreferrer" aria-label="WhatsApp" class="footer-social-wa"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413z"/></svg></a>
        </div>
      </div>
      <div>
        <div class="footer-title">Explore</div>
        <a href="../">Home</a><a href="../tours">All Experiences</a><a href="../paquete">Multi-Day Journeys</a><a href="../hotels">Hotels</a><a href="../transport">Transport</a><a href="../guides">Expert Guides</a><a href="../about">Our Story</a><a href="../Blogs">Insider Guide</a><a href="../travel-insurance">Travel Insurance</a>
        <div class="footer-title footer-title-spaced">Legal</div>
        <a href="../Terminosycondiciones">Terms &amp; Conditions</a><a href="../politicasdecancelacion">Booking &amp; Cancellation Policy</a><a href="../politicasdeprivacidad">Privacy Policy</a>
      </div>
      <div>
        <div class="footer-title">Get in Touch</div>
        <div class="footer-contact">
          <p>Guanacaste, Costa Rica</p>
          <p><a href="tel:+50688566325">+506 8856-6325</a></p>
          <p><a href="mailto:info@wildpapagayo.com">info@wildpapagayo.com</a></p>
        </div>
        <p class="footer-ict">Costa Rica - ICT License #491</p>
      </div>
      <div>
        <div class="footer-title">Trip Planning Tips</div>
        <p>Real trip-planning tips, seasonal advice and new tours from our local team. No spam, unsubscribe anytime.</p>
        <div class="newsletter-form">
          <label for="newsletterEmail" class="sr-only">Email</label>
          <input id="newsletterEmail" name="newsletterEmail" type="email" placeholder="Your email address" required>
          <button class="btn-newsletter" type="button" onclick="enviarNewsletter()">Join</button>
        </div>
      </div>
    </div>
    <div class="container footer-bottom">
      &copy; <span id="year"></span> Wild Papagayo. All rights reserved.
    </div>
  </footer>

  <a href="https://wa.me/50688566325?text=Hello%20Wild%20Papagayo!%20I%20want%20to%20plan%20a%20private%20Costa%20Rica%20experience." class="whatsapp-float" target="_blank" rel="noopener noreferrer" aria-label="Chat with us on WhatsApp">
    <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413z"/></svg>
  </a>

  <script>
    document.getElementById('year').textContent = new Date().getFullYear();
    // Alternate h2 underline: every other h2 gets no gold line
    document.querySelectorAll('.blog-body h2').forEach(function(h2, i) {
      if (i % 2 === 1) h2.classList.add('h2-plain');
    });
  </script>
  <script src="../script.js" defer></script>
    <script src="../assistant-widget.js" defer></script>
</body>
</html>
'@

# ── Table of contents: tags each <h2> with a slug id, returns modified html + heading list ──
function Add-HeadingIds {
    param([string]$Html)
    $headings = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Html)) { return [pscustomobject]@{ html = $Html; headings = $headings } }
    $evaluator = {
        param($m)
        $text = $m.Groups[1].Value -replace '<[^>]+>', ''
        $slug = ($text.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
        if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "section-$($headings.Count + 1)" }
        $headings.Add([pscustomobject]@{ id = $slug; text = $text })
        return "<h2 id=`"$slug`">$($m.Groups[1].Value)</h2>"
    }
    $result = [regex]::Replace($Html, '<h2>(.*?)</h2>', $evaluator)
    return [pscustomobject]@{ html = $result; headings = $headings }
}

# ── Related articles: score by shared hotel/tour/destination ids, fall back to category, then recency ──
function Get-RelatedArticles {
    param($Current, $All)
    # Optional editorial pin: an article may list its Keep Reading slugs explicitly
    # ("related_slugs" in blog-data.json). Pins are used as written, in order, and an
    # invalid pin fails generation instead of being silently replaced.
    $pinProp = $Current.PSObject.Properties['related_slugs']
    if ($pinProp -and $null -ne $pinProp.Value) {
        # Any error while resolving pins must stop generation, never fall through to the algorithm.
        $ErrorActionPreference = 'Stop'
        $pins = @($pinProp.Value)
        if ($pins.Count -eq 0) { throw "related_slugs for '$($Current.slug)' is empty" }
        $pinned = @()
        foreach ($ps in $pins) {
            $psl = [string]$ps
            if ($psl -eq [string]$Current.slug) { throw "related_slugs for '$($Current.slug)' contains the article itself" }
            if (-not $articlePos.ContainsKey($psl)) { throw "related_slugs for '$($Current.slug)' references unknown slug '$psl'" }
            if (@($pinned | Where-Object { $_.slug -eq $psl }).Count -gt 0) { throw "related_slugs for '$($Current.slug)' repeats '$psl'" }
            $pinned += $All[$articlePos[$psl]]
        }
        return $pinned
    }
    $scored = foreach ($other in $All) {
        if ($other.slug -eq $Current.slug) { continue }
        $score = 0
        foreach ($field in @('destination_ids', 'hotel_ids', 'tour_ids')) {
            $mine = @($Current.$field)
            $theirs = @($other.$field)
            $shared = @($mine | Where-Object { $theirs -contains $_ })
            $score += $shared.Count * 3
        }
        if ($Current.category -eq $other.category) { $score += 1 }
        [pscustomobject]@{ article = $other; score = $score; pos = $articlePos[[string]$other.slug] }
    }
    # Explicit total order: score descending, then original blog-data.json position ascending.
    $ranked = @($scored | Sort-Object @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.pos }; Ascending = $true })
    $top = @($ranked | Where-Object { $_.score -gt 0 } | Select-Object -First 3)
    if ($top.Count -lt 3) {
        $fillerNeeded = 3 - $top.Count
        $usedSlugs = @($top | ForEach-Object { $_.article.slug })
        $filler = @($ranked | Where-Object { $_.score -eq 0 -and $usedSlugs -notcontains $_.article.slug } | Select-Object -First $fillerNeeded)
        $top = @($top) + @($filler)
    }
    return @($top | ForEach-Object { $_.article })
}

$articleIndex = -1
foreach ($a in $articles) {
    $articleIndex++
    if ($singleSlug -and $a.slug -ne $singleSlug) { continue }
    # Mirrors the status gate already used by hotel-generator.ps1 /
    # hotels-index-generator.ps1 (status "disabled") and tour-generator.ps1
    # (status "active") -- an article whose status is explicitly something
    # other than "published" (e.g. "draft") is content that isn't cleared to
    # go live, so it must not get an HTML page, sitemap entry or a place in
    # Bubu's knowledge. Missing status defaults to published for backward
    # compatibility with older records that never had the field.
    if ($a.status -and [string]$a.status -ne 'published') { continue }

    $slug      = $a.slug
    $pageTitle = "$($a.seo_title_pro) | Wild Papagayo"
    $canonUrl  = "$siteUrl/blog/$slug"
    $ogImage   = "$siteUrl/$($a.image_top)"
    # Some older articles only ever had the human-readable "date" field filled
    # in, never "iso_date" -- derive it from the real date rather than leaving
    # the schema's datePublished empty (empty datePublished fails schema
    # validation, e.g. liberia-airport-transfer-guide.html).
    $isoDate = if ($a.iso_date) {
        $a.iso_date
    } elseif ($a.date) {
        try { ([DateTime]::Parse($a.date)).ToString('yyyy-MM-ddT00:00:00Z') } catch { "" }
    } else { "" }

    # Reading time in hero meta
    $readTimeHtml = ""
    if ($a.readTime) {
        $readTimeHtml = "<span class=`"blog-meta-sep`">&middot;</span><span class=`"blog-meta-read`">$($a.readTime) min read</span>"
    }

    # Share URLs
    $waEnc   = [Uri]::EscapeDataString($a.title + " - " + $canonUrl)
    $waShare = "https://wa.me/?text=$waEnc"
    $fbEnc   = [Uri]::EscapeDataString($canonUrl)
    $fbShare = "https://www.facebook.com/sharer/sharer.php?u=$fbEnc"

    # Schema JSON strings
    $schemaTitleClean = ($a.title -replace '\s+', ' ').Trim()
    $schemaDescClean  = ($a.seo_description -replace '\s+', ' ').Trim()
    $schemaArticleObj = [ordered]@{
        '@context'='https://schema.org'; '@type'='BlogPosting'; '@id'="$canonUrl#article"
        mainEntityOfPage=@{'@type'='WebPage';'@id'=$canonUrl}
        headline=$schemaTitleClean; description=$schemaDescClean; image=@($ogImage)
        datePublished=$isoDate; dateModified=$isoDate
        author=@{'@type'='Organization';name=$a.author_name;url='https://wildpapagayo.com/'}
        publisher=@{'@type'='Organization';'@id'='https://wildpapagayo.com/#organization';name='Wild Papagayo';logo=@{'@type'='ImageObject';url='https://wildpapagayo.com/images/logo-wildpapagayo-nav.webp';width=450;height=300}}
        articleSection=$a.category; url=$canonUrl
    }
    $schemaArticle = $schemaArticleObj | ConvertTo-Json -Depth 10 -Compress
    $schemaBreadcrumbObj = [ordered]@{
        '@context'='https://schema.org'; '@type'='BreadcrumbList'
        itemListElement=@(
            @{'@type'='ListItem';position=1;name='Home';item='https://wildpapagayo.com/'}
            @{'@type'='ListItem';position=2;name='Insider Guide';item='https://wildpapagayo.com/Blogs'}
            @{'@type'='ListItem';position=3;name=$schemaTitleClean;item=$canonUrl}
        )
    }
    $schemaBreadcrumb = $schemaBreadcrumbObj | ConvertTo-Json -Depth 10 -Compress

    # ── Optional content blocks ──

    $middleImg = ""
    if ($a.image_middle) {
        $middleImg = "<figure class=`"blog-figure`"><img src=`"../$($a.image_middle)`" alt=`"$($a.image_middle_alt)`" width=`"1200`" height=`"675`" loading=`"lazy`" decoding=`"async`"><figcaption>$($a.image_middle_alt)</figcaption></figure>"
    }

    $bottomImg = ""
    if ($a.image_bottom) {
        $bottomImg = "<figure class=`"blog-figure`"><img src=`"../$($a.image_bottom)`" alt=`"$($a.image_bottom_alt)`" width=`"1200`" height=`"675`" loading=`"lazy`" decoding=`"async`"><figcaption>$($a.image_bottom_alt)</figcaption></figure>"
    }

    # Travel tip — gold callout box
    $travelTipHtml = ""
    if ($a.travel_tip) {
        $travelTipHtml = "<div class=`"blog-tip-box`"><div class=`"blog-tip-label`">Local Expert Tip</div><p>$($a.travel_tip)</p></div>"
    }

    # Quick facts — checklist card
    $quickFactsHtml = ""
    if ($a.quick_facts -and $a.quick_facts.Count -gt 0) {
        $items = ($a.quick_facts | ForEach-Object { "<li>$_</li>" }) -join ""
        $quickFactsHtml = "<div class=`"blog-facts-box`"><div class=`"blog-facts-title`">Quick Facts</div><ul class=`"blog-facts-list`">$items</ul></div>"
    }

    # Packing list — What to Bring checklist
    $packingListHtml = ""
    if ($a.packing_list -and $a.packing_list.Count -gt 0) {
        $items = ($a.packing_list | ForEach-Object { "<li>$_</li>" }) -join ""
        $packingListHtml = "<div class=`"blog-facts-box`"><div class=`"blog-facts-title`">What to Bring</div><ul class=`"blog-facts-list`">$items</ul></div>"
    }

    # Did you know — blue callout card
    $didYouKnowHtml = ""
    if ($a.did_you_know) {
        $didYouKnowHtml = "<div class=`"blog-dyk-box`"><div class=`"blog-dyk-label`">Did You Know?</div><p>$($a.did_you_know)</p></div>"
    }

    # Best for — tag pills
    $bestForHtml = ""
    if ($a.best_for -and $a.best_for.Count -gt 0) {
        $tags = ($a.best_for | ForEach-Object { "<span class=`"blog-best-for-tag`">$_</span>" }) -join ""
        $bestForHtml = "<div class=`"blog-best-for`"><span class=`"blog-best-for-label`">Best For</span>$tags</div>"
    }

    # Decision Engine — "Recommended For Your Trip" tour matching.
    # When the article explicitly lists tour_ids, show exactly those tours (in
    # the order authored) and nothing else -- an article that names its own
    # tours has already made the editorial decision, and backfilling the
    # remaining slots from unrelated tours undermines that decision (e.g. a
    # Rincón de la Vieja article padded out with an unrelated Rio Negro tour).
    # Only articles with NO explicit tour_ids fall back to profile/destination
    # scoring, so older/simpler articles keep working exactly as before.
    $recommendedForTripHtml = ""
    if ($toursForRec.Count -gt 0) {
        $articleTourIds = @($a.tour_ids)
        $articleProfiles = @($a.traveler_profile_ids)
        $articleDestIds = @($a.destination_ids)
        $recPin = $a.PSObject.Properties['recommended_tour_ids']
        if ($recPin -and $null -ne $recPin.Value) {
            # Editorial pin ("recommended_tour_ids"): exactly these tours, in this order (validated up front).
            $topTours = @(@($recPin.Value) | ForEach-Object {
                $pinTid = [string]$_
                $t = $toursForRec | Where-Object { $_.id -eq $pinTid } | Select-Object -First 1
                [pscustomobject]@{ tour = $t; score = 10 }
            })
        } elseif ($articleTourIds.Count -gt 0) {
            $topTours = @($articleTourIds | ForEach-Object {
                $tid = $_
                $t = $toursForRec | Where-Object { $_.id -eq $tid } | Select-Object -First 1
                if ($t) { [pscustomobject]@{ tour = $t; score = 10 } }
            } | Select-Object -First 4)
        } else {
            # An article tagged for infants/toddlers must never surface a physically
            # demanding tour just because it also carries a generic "Families" tag --
            # a 7km rainforest trail or a canopy zip line isn't a fit for a baby, no
            # matter how well the destination/profile words otherwise match.
            $isInfantProfile = @($articleProfiles | Where-Object { $_ -match 'baby|infant|toddler' }).Count -gt 0
            $tourIdx = -1
            $scoredTours = foreach ($t in $toursForRec) {
                $tourIdx++
                if ($isInfantProfile -and ($t.difficulty -notin @('Easy') -or $t.minimum_age -gt 2)) { continue }
                $score = 0
                foreach ($profileId in $articleProfiles) {
                    $profileWords = Get-WildWordSet ($profileId -replace '-', ' ')
                    $matched = $false
                    foreach ($bf in $t.best_for) {
                        $bfWords = Get-WildWordSet $bf
                        foreach ($pw in $profileWords) {
                            foreach ($bw in $bfWords) {
                                if ($bw.StartsWith($pw) -or $pw.StartsWith($bw)) { $matched = $true; break }
                            }
                            if ($matched) { break }
                        }
                        if ($matched) { break }
                    }
                    if ($matched) { $score += 3 }
                }
                $sharedDest = @($articleDestIds | Where-Object { $t.destination_ids -contains $_ })
                $score += $sharedDest.Count * 2
                [pscustomobject]@{ tour = $t; score = $score; idx = $tourIdx }
            }
            # Explicit total order: score descending, then tour source-array position ascending
            # (Windows PowerShell 5.1 Sort-Object is not stable for tied scores).
            $topTours = @($scoredTours | Where-Object { $_.score -gt 0 } | Sort-Object @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.idx }; Ascending = $true } | Select-Object -First 3)
        }
        if ($topTours.Count -gt 0) {
            $recCards = ($topTours | ForEach-Object {
                $t = $_.tour
                "<a class=`"blog-rec-card`" href=`"$($t.url)`"><img src=`"../$($t.image)`" alt=`"$($t.name)`" loading=`"lazy`" decoding=`"async`"><div class=`"blog-rec-card-body`"><span>$($t.category)</span><h3>$($t.name)</h3><p>$($t.description)</p></div></a>"
            }) -join ""
            $recommendedForTripHtml = "<div class=`"blog-recommended`"><h2>Recommended For Your Trip</h2><div class=`"blog-rec-grid`">$recCards</div></div>"
        }
    }
    # Opt-in placement override -- default keeps this block near the top of the
    # page (unchanged behavior for every other article). An article can instead
    # request it inline, after the main body and before content_block_3, when
    # an informational-first article needs the commercial block to appear only
    # once the reader has finished the core content.
    $recPlacement = if ($a.recommended_for_trip_placement) { [string]$a.recommended_for_trip_placement } else { 'top' }
    $recommendedForTripTopHtml = $recommendedForTripHtml
    $recommendedForTripInlineHtml = ""
    if ($recPlacement -eq 'inline') {
        $recommendedForTripTopHtml = ""
        $recommendedForTripInlineHtml = $recommendedForTripHtml
    }

    # Dynamic CTA -- the WhatsApp button reflects what THIS article is actually
    # about (a specific hotel > tour > season) instead of one generic message
    # on every page. Falls back to the article's own authored cta_text/cta_url
    # when no tags give a more specific hook.
    $dynamicCtaText = [string]$a.cta_text
    $dynamicCtaUrl = [string]$a.cta_url
    $ctaHotelId = @($a.hotel_ids) | Select-Object -First 1
    $ctaTourId = @($a.tour_ids) | Select-Object -First 1
    $ctaSeasonId = @($a.season_ids) | Select-Object -First 1
    # cta_locked: this article's own cta_text/cta_url was hand-checked against its
    # actual topic -- skip the hotel/tour/season auto-hook so it can't drift away
    # from what the article is really about (e.g. a transport-planning article
    # getting hijacked into promoting a random tagged tour).
    if ($a.cta_locked -eq $true) {
        # keep $dynamicCtaText / $dynamicCtaUrl as authored, skip all overrides below
    } elseif ($ctaHotelId -and $hotelNameById.ContainsKey($ctaHotelId)) {
        $hotelName = $hotelNameById[$ctaHotelId]
        $dynamicCtaText = "Need Private Transportation from $($hotelName)?"
        $dynamicCtaUrl = 'https://wa.me/50688566325?text=' + [Uri]::EscapeDataString("Hello Wild Papagayo! I'm staying at $hotelName and would love help planning tours and transfers.")
    } elseif ($ctaTourId) {
        $ctaTour = $toursForRec | Where-Object { $_.id -eq $ctaTourId } | Select-Object -First 1
        if ($ctaTour) {
            $dynamicCtaText = "Want to Experience $($ctaTour.name)?"
            $dynamicCtaUrl = 'https://wa.me/50688566325?text=' + [Uri]::EscapeDataString("Hello Wild Papagayo! I'm interested in $($ctaTour.name) and would love more details.")
        }
    } elseif ($ctaSeasonId -and $monthDisplayById.ContainsKey($ctaSeasonId)) {
        $seasonLabel = $monthDisplayById[$ctaSeasonId]
        $dynamicCtaText = "Need Help Planning a $seasonLabel Trip?"
        $dynamicCtaUrl = 'https://wa.me/50688566325?text=' + [Uri]::EscapeDataString("Hello Wild Papagayo! I'm planning a trip during $seasonLabel and would love local advice.")
    }

    # FAQ block
    $faqBlock = ""
    $schemaFaq = ""
    if ($a.content_block_faq) {
        $faqBlock = "<section class=`"blog-faq`">$($a.content_block_faq)</section>"
        $faqMatches = [regex]::Matches($a.content_block_faq, '<h3[^>]*>(.*?)</h3>\s*<p[^>]*>(.*?)</p>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($faqMatches.Count -gt 0) {
            $faqEntities = @($faqMatches | ForEach-Object {
                $q = [regex]::Replace($_.Groups[1].Value, '<[^>]+>', '').Trim()
                $ans = [regex]::Replace($_.Groups[2].Value, '<[^>]+>', '').Trim()
                @{'@type'='Question';name=$q;acceptedAnswer=@{'@type'='Answer';text=$ans}}
            })
            $faqSchemaObj = @{'@context'='https://schema.org';'@type'='FAQPage';mainEntity=$faqEntities}
            $schemaFaq = '<script type="application/ld+json">' + ($faqSchemaObj | ConvertTo-Json -Depth 10 -Compress) + '</script>'
        }
    }

    # Internal links — related content navigation
    $internalLinksHtml = ""
    if ($a.internal_links -and $a.internal_links.Count -gt 0) {
        $linksList = ($a.internal_links | ForEach-Object {
            $linkText = $_.text
            $linkUrl  = $_.url
            if ($linkText -and $linkUrl) {
                "<li><a href=`"$linkUrl`">$linkText</a></li>"
            }
        }) -join ""
        if ($linksList) {
            $internalLinksHtml = "<nav class=`"blog-related-links`" aria-label=`"Related content`"><h2 class=`"blog-related-links-title`">Continue Planning</h2><ul class=`"blog-related-links-list`">$linksList</ul></nav>"
        }
    }

    # ── Table of contents: tag h2s in each content block, build nav if 2+ headings ──
    $tagged1 = Add-HeadingIds $a.content_block_1
    $tagged2 = Add-HeadingIds $a.content_block_2
    $tagged3 = Add-HeadingIds $a.content_block_3
    $allHeadings = @($tagged1.headings.ToArray()) + @($tagged2.headings.ToArray()) + @($tagged3.headings.ToArray())
    $tocHtml = ""
    if ($allHeadings.Count -ge 2) {
        $tocItems = ($allHeadings | ForEach-Object { "<li><a href=`"#$($_.id)`">$($_.text)</a></li>" }) -join ""
        $tocHtml = "<nav class=`"blog-toc`" aria-label=`"Table of contents`"><p class=`"blog-toc-title`">Contents</p><ol>$tocItems</ol></nav>"
    }

    # ── Last updated ──
    $lastUpdatedHtml = ""
    if ($isoDate) {
        try { $lastUpdatedHtml = "Updated " + ([datetime]$isoDate).ToString('MMMM yyyy', [System.Globalization.CultureInfo]::GetCultureInfo('en-US')) } catch { $lastUpdatedHtml = "" }
    }

    # ── Related articles: top 3 by shared hotel/tour/destination, falls back to category/recency ──
    $related = @(Get-RelatedArticles -Current $a -All $articles)
    $relatedArticlesHtml = ""
    if ($related.Count -gt 0) {
        $cards = ($related | ForEach-Object {
            $rImg = if ($_.image_top) { "../$($_.image_top)" } else { '' }
            "<a class=`"blog-related-card`" href=`"$($_.slug)`"><img src=`"$rImg`" alt=`"$($_.image_top_alt)`" loading=`"lazy`"><div><small>$($_.category)</small><h4>$($_.title)</h4></div></a>"
        }) -join ""
        $relatedArticlesHtml = "<section class=`"blog-related-articles`"><h3 class=`"blog-related-articles-title`">Keep Reading</h3><div class=`"blog-related-grid`">$cards</div></section>"
    }

    # ── Previous / Next navigation (list order in blog-data.json) ──
    $prevNextHtml = ""
    $prevPart = if ($articleIndex -gt 0) { $articles[$articleIndex - 1] } else { $null }
    $nextPart = if ($articleIndex -lt ($articles.Count - 1)) { $articles[$articleIndex + 1] } else { $null }
    if ($prevPart -or $nextPart) {
        $prevHtml = if ($prevPart) { "<a href=`"$($prevPart.slug)`"><small>&larr; Previous</small><strong>$($prevPart.title)</strong></a>" } else { "<span></span>" }
        $nextHtml = if ($nextPart) { "<a class=`"blog-next`" href=`"$($nextPart.slug)`"><small>Next &rarr;</small><strong>$($nextPart.title)</strong></a>" } else { "<span></span>" }
        $prevNextHtml = "<nav class=`"blog-prevnext`" aria-label=`"Article navigation`">$prevHtml$nextHtml</nav>"
    }

    # ── Alternate image position by article id ──
    # Odd  (1, 3, 5…): content_1 → travel_tip → image → content_2
    # Even (2, 4, 6…): image → content_1 → travel_tip → content_2
    if ($a.id % 2 -eq 1) {
        $articleBodyHtml = "<section>$($tagged1.html)</section>`n$travelTipHtml`n$middleImg`n<section>$($tagged2.html)</section>"
    } else {
        $articleBodyHtml = "$middleImg`n<section>$($tagged1.html)</section>`n$travelTipHtml`n<section>$($tagged2.html)</section>"
    }
    if ($recommendedForTripInlineHtml) {
        $articleBodyHtml += "`n$recommendedForTripInlineHtml"
    }

    # ── Substitute all placeholders ──
    $html = $template
    $html = $html.Replace('__SLUG__',              $slug)
    $html = $html.Replace('__PAGE_TITLE__',        $pageTitle)
    $html = $html.Replace('__SEO_DESC__',          $a.seo_description)
    $html = $html.Replace('__SEO_KEYWORDS__',      $a.seo_keywords)
    $html = $html.Replace('__AUTHOR_NAME__',       $a.author_name)
    $html = $html.Replace('__AUTHOR_BADGE__',      $a.author_badge)
    $html = $html.Replace('__CANONICAL_URL__',     $canonUrl)
    $html = $html.Replace('__OG_IMAGE__',          $ogImage)
    $html = $html.Replace('__OG_IMAGE_ALT__',      $a.image_top_alt)
    $html = $html.Replace('__CATEGORY__',          $a.category)
    $html = $html.Replace('__ISO_DATE__',          $isoDate)
    $html = $html.Replace('__HERO_IMAGE__',        $a.image_top)
    $html = $html.Replace('__TITLE__',             $a.title)
    $html = $html.Replace('__DATE__',              $a.date)
    $html = $html.Replace('__READ_TIME__',         $readTimeHtml)
    $html = $html.Replace('__EXCERPT__',           $a.excerpt)
    $html = $html.Replace('__LAST_UPDATED__',      $lastUpdatedHtml)
    $html = $html.Replace('__TABLE_OF_CONTENTS__', $tocHtml)
    $html = $html.Replace('__QUICK_FACTS__',       $quickFactsHtml)
    $html = $html.Replace('__BEST_FOR__',          $bestForHtml)
    $html = $html.Replace('__RECOMMENDED_FOR_TRIP__', $recommendedForTripTopHtml)
    $html = $html.Replace('__ARTICLE_BODY__',      $articleBodyHtml)
    $html = $html.Replace('__PACKING_LIST__',      $packingListHtml)
    $html = $html.Replace('__DID_YOU_KNOW__',      $didYouKnowHtml)
    $html = $html.Replace('__BOTTOM_IMG__',        $bottomImg)
    $html = $html.Replace('__CONTENT_3__',         $tagged3.html)
    $html = $html.Replace('__INTERNAL_LINKS__',    $internalLinksHtml)
    $html = $html.Replace('__RELATED_ARTICLES__',  $relatedArticlesHtml)
    $html = $html.Replace('__PREV_NEXT_NAV__',     $prevNextHtml)
    $html = $html.Replace('__FAQ_BLOCK__',         $faqBlock)
    $html = $html.Replace('__WA_SHARE__',          $waShare)
    $html = $html.Replace('__FB_SHARE__',          $fbShare)
    $ctaIntent = if (@($a.activity_ids) -contains 'airport-transfer') { 'airport_transfer' } else { 'book_tour' }
    $html = $html.Replace('__CTA_URL__',           $dynamicCtaUrl)
    $html = $html.Replace('__CTA_TEXT__',          $dynamicCtaText)
    $html = $html.Replace('__CTA_INTENT__',        $ctaIntent)
    $html = $html.Replace('__SCHEMA_ARTICLE__',    $schemaArticle)
    $html = $html.Replace('__SCHEMA_BREADCRUMB__', $schemaBreadcrumb)
    $html = $html.Replace('__SCHEMA_FAQ__',        $schemaFaq)

    $outPath = Join-Path $outDir "$slug.html"
    Write-FileIfChanged -Path $outPath -Content $html
    Write-Host "Generated: blog/$slug.html"
}

Write-Host ""
if ($singleSlug) { Write-Host "Done! single-article mode: blog/$singleSlug.html only" }
else { Write-Host "Done! $($articles.Count) static article(s) in /blog/" }


# Wild Engine: generate destination pages using reusable components (full mode only)
$destinationGenerator = Join-Path $PSScriptRoot "destination-generator.ps1"
if ($singleSlug) {
    # single-article mode: destinations are not regenerated
} elseif (Test-Path $destinationGenerator) {
    & $destinationGenerator
} else {
    Write-Warning "Destination generator not found: $destinationGenerator"
}

# ============================================================
# Wild Engine: automatic rss.xml
# (sitemap.xml is owned solely by sitemap-generator.ps1, which runs
# later in deploy-package.ps1 and scans real output folders with
# correct extensionless canonical URLs -- do not duplicate it here.)
# ============================================================

function Get-XmlEscaped {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Security.SecurityElement]::Escape($Text)
}

# RSS feed - most recent first. Fully deterministic: the publication instant is an explicit
# UTC value (never machine-local time, never Get-Date) and ties are broken by the article's
# position in blog-data.json. Articles without iso_date use their human-readable "date".
function Get-ArticleUtcDate {
    param($Article)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $iso = $Article.iso_date
    $parsed = [datetime]::MinValue
    if ($iso -is [datetime]) { return $iso.ToUniversalTime() }
    if ($iso) {
        if (-not [datetime]::TryParse([string]$iso, $inv, $styles, [ref]$parsed)) { throw "Article '$($Article.slug)': cannot parse iso_date '$iso'" }
        return $parsed
    }
    if ($Article.date) {
        if (-not [datetime]::TryParseExact([string]$Article.date, 'MMMM d, yyyy', $inv, $styles, [ref]$parsed)) { throw "Article '$($Article.slug)': no iso_date and cannot parse date '$($Article.date)'" }
        return $parsed
    }
    throw "Article '$($Article.slug)' has neither iso_date nor date"
}
if ((-not $singleSlug) -or $RefreshRss) {
    $rssItems = New-Object System.Collections.Generic.List[string]
    $rssRows = for ($ri = 0; $ri -lt $articles.Count; $ri++) { [pscustomobject]@{ article = $articles[$ri]; utc = (Get-ArticleUtcDate $articles[$ri]); pos = $ri } }
    $sortedForRss = @($rssRows | Sort-Object @{ Expression = { $_.utc }; Descending = $true }, @{ Expression = { $_.pos }; Ascending = $true })
    foreach ($row in $sortedForRss) {
        $ra = $row.article
        $pubDate = $row.utc.ToString('r', [System.Globalization.CultureInfo]::InvariantCulture)
        $link = "$siteUrl/blog/$($ra.slug)"
        $rssItems.Add("  <item><title>$(Get-XmlEscaped $ra.title)</title><link>$link</link><guid>$link</guid><pubDate>$pubDate</pubDate><description>$(Get-XmlEscaped $ra.excerpt)</description></item>")
    }
    $rssXml = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<rss version=`"2.0`"><channel><title>Wild Papagayo Insider Guide</title><link>$siteUrl/Blogs</link><description>Costa Rica travel guides, tours and hotel insight from Wild Papagayo.</description><language>en-us</language>`n$($rssItems -join "`n")`n</channel></rss>`n"
    Write-FileIfChanged -Path (Join-Path $PSScriptRoot 'rss.xml') -Content $rssXml
    Write-Host "rss.xml up to date ($($rssItems.Count) items)"
}
