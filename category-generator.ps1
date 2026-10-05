# ============================================================
# Wild Papagayo - Category Engine v1.0
# Generates one static, crawlable page per blog category at
# /categories/<slug>.html -- a real indexable URL for each
# category, instead of relying on the client-side JS filter on
# Blogs.html (which produces no distinct URL for search engines).
# ============================================================
$ErrorActionPreference = "Stop"

function Write-FileIfChanged {
    param([string]$Path, [string]$Content)
    if ((Test-Path $Path) -and ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) -ceq $Content)) { return }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}
$root = $PSScriptRoot
$templatePath = Join-Path $root "templates/category.html"
$outputDir = Join-Path $root "categories"
$blogPath = Join-Path $root "blog-data.json"
$siteUrl = "https://wildpapagayo.com"

if (-not (Test-Path $templatePath)) { throw "Missing template: $templatePath" }
New-Item -ItemType Directory -Force $outputDir | Out-Null

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }
function ConvertTo-HtmlSafe([object]$value) { return [System.Net.WebUtility]::HtmlEncode([string]$value) }
function Component([string]$name) {
    $p = Join-Path $root "templates/components/$name.html"
    if (-not (Test-Path $p)) { throw "Missing component: $p" }
    return [System.IO.File]::ReadAllText($p)
}

$dimensionsPath = Join-Path $root "image-dimensions.json"
$imageDimensions = if (Test-Path $dimensionsPath) { [System.IO.File]::ReadAllText($dimensionsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } else { $null }
function Get-ImageDimAttrs {
    param([string]$Src)
    if ($null -eq $imageDimensions) { return '' }
    $fileName = [System.IO.Path]::GetFileName($Src)
    $prop = $imageDimensions.PSObject.Properties[$fileName]
    if ($null -eq $prop) { return '' }
    return ' width="' + [string]$prop.Value.width + '" height="' + [string]$prop.Value.height + '"'
}

$template = [System.IO.File]::ReadAllText($templatePath)
$header = Component "header"
$footer = Component "footer"
$ctaTemplate = Component "cta"
$articles = @(Read-Utf8Json $blogPath)
# Same status gate blog-generator.ps1 applies before rendering a page: an
# article whose status is explicitly something other than "published"
# (e.g. "draft") never gets its own page, so category listings must not
# link to it either. Missing status defaults to published for backward
# compatibility with older records that never had the field.
$articles = @($articles | Where-Object { -not $_.status -or [string]$_.status -eq 'published' })
$heroImage = "images/luxury-costa-rica-tours-hero.webp"

$categoriesPath = Join-Path $root "knowledge/categories.json"
if (-not (Test-Path $categoriesPath)) { throw "Missing category list: $categoriesPath" }
$categories = @(Read-Utf8Json $categoriesPath)

# Auto-create any category an article uses that doesn't exist yet -- writing a
# new category name onto an article is enough; nobody has to pre-create it in
# the CMS first. Persisted back to knowledge/categories.json so it becomes a
# real, permanent, editable category from then on (not regenerated from
# scratch and not silently dropped the next time this runs).
$knownNames = @($categories | ForEach-Object { [string]$_.name })
$usedNames = @($articles | ForEach-Object { [string]$_.category } | Where-Object { $_ } | Select-Object -Unique)
$newNames = @($usedNames | Where-Object { $knownNames -notcontains $_ })
if ($newNames.Count -gt 0) {
    foreach ($name in $newNames) {
        $slug = $name.ToLowerInvariant() -replace '[^a-z0-9]+','-'
        $slug = $slug.Trim('-')
        $categories += [pscustomobject]@{ slug = $slug; name = $name; description = "Articles about $name." }
        Write-Host "Auto-created category: $name ($slug)" -ForegroundColor Cyan
    }
    $json = $categories | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($categoriesPath, $json, [System.Text.UTF8Encoding]::new($false))
}

$pills = ($categories | ForEach-Object { "<a class=`"category-pill`" href=`"$($_.slug)`">$(ConvertTo-HtmlSafe $_.name)</a>" }) -join "`n"

$generated = 0
foreach ($cat in $categories) {
    $matched = @($articles | Where-Object { [string]$_.category -eq $cat.name })
    if ($matched.Count -eq 0) { continue }

    $canonical = "$siteUrl/categories/$($cat.slug)"
    $cards = @()
    foreach ($a in $matched) {
        $articleImg = if ($a.image_top -and (Test-Path (Join-Path $root $a.image_top))) { $a.image_top } else { $heroImage }
        $cards += @"
<a class="wp-destination-experience-card" href="../blog/$($a.slug)">
  <img class="wp-destination-experience-image" src="../$articleImg" alt="$(ConvertTo-HtmlSafe $a.image_top_alt)"$(Get-ImageDimAttrs $articleImg) loading="lazy" decoding="async">
  <div class="wp-destination-experience-content">
    <span class="wp-destination-experience-label">$(ConvertTo-HtmlSafe $cat.name)</span>
    <h3>$(ConvertTo-HtmlSafe $a.title)</h3>
    <p>$(ConvertTo-HtmlSafe $a.excerpt)</p>
    <span class="wp-destination-experience-link">Read Article &rarr;</span>
  </div>
</a>
"@
    }

    $pillsForPage = ($categories | ForEach-Object {
        $activeClass = if ($_.slug -eq $cat.slug) { ' is-active' } else { '' }
        "<a class=`"category-pill$activeClass`" href=`"$($_.slug)`">$(ConvertTo-HtmlSafe $_.name)</a>"
    }) -join "`n"

    $cta = $ctaTemplate.Replace('__DESTINATION_NAME__', $cat.name).Replace('__CTA_URL__', "https://wa.me/50688566325?text=$([Uri]::EscapeDataString("Hello Wild Papagayo! I've been reading about $($cat.name) and would love local help planning my trip."))")
    $schemaObj = [ordered]@{'@context'='https://schema.org';'@type'='CollectionPage';name=$cat.name;description=$cat.description;url=$canonical}
    $schema = $schemaObj | ConvertTo-Json -Compress

    $html = $template.Replace('__COMPONENT_HEADER__', $header).Replace('__COMPONENT_FOOTER__', $footer).Replace('__COMPONENT_CTA__', $cta)
    $replacements = @{
        '__SEO_TITLE__'          = "$($cat.name) | Wild Papagayo Insider Guide"
        '__SEO_DESCRIPTION__'    = $cat.description
        '__CANONICAL__'          = $canonical
        '__SCHEMA__'             = $schema
        '__HERO_IMAGE__'         = $heroImage
        '__CATEGORY_NAME__'      = $cat.name
        '__CATEGORY_DESCRIPTION__' = $cat.description
        '__CATEGORY_PILLS__'     = $pillsForPage
        '__ARTICLE_CARDS__'      = ($cards -join "`n")
    }
    foreach ($key in $replacements.Keys) { $html = $html.Replace($key, $replacements[$key]) }
    $out = Join-Path $outputDir "$($cat.slug).html"
    Write-FileIfChanged -Path $out -Content $html
    Write-Host "Generated category: categories/$($cat.slug).html ($($matched.Count) articles)"
    $generated++
}
Write-Host "Category Engine complete: $generated page(s)."
