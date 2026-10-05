param(
    [int]$Port = 8765,
    [switch]$NoOpen
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$webRoot = Join-Path $root 'wild-cms'
$baseUrl = "http://localhost:$Port/"

if (-not (Test-Path $webRoot)) {
    throw "Control Center files not found: $webRoot"
}

function Read-JsonSafe {
    param([string]$Path, $Fallback = $null)
    if (-not (Test-Path $Path)) { return $Fallback }
    try {
        $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        # Parenthesize the pipeline -- "return $raw | ConvertFrom-Json" (unparenthesized)
        # silently corrupts array results when a caller wraps the call in @(...):
        # the array gets boxed into a single {value:[...],Count:N} object instead of
        # being unrolled. This bit Save-Question and Publish-Article in production.
        return ($raw | ConvertFrom-Json)
    }
    catch { return $Fallback }
}

function Get-PropertyValue {
    param($Object, [string]$Name, $Fallback = $null)
    if ($null -eq $Object) { return $Fallback }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Fallback
}

function Get-CanonicalTourFromPrice {
    # Same "public starting price" contract tour-generator.ps1's teaser,
    # tours-catalog-pricing-sync.ps1's catalog cards and
    # recommendation-engine.ps1's Get-CanonicalTourFromPrice already use:
    # the minimum pp_2/pp_3/pp_4plus across every ACTIVE option for this
    # tour in tour-pricing.json. This is the real, commercial, Excel-
    # sourced tour price -- read-only here, never written by the CMS.
    # Returns $null (never 0) when the tour has no entry, no ACTIVE
    # option, or is MANUAL QUOTE only.
    param([string]$TourId)
    $pricingJsonPath = Join-Path $root 'tour-pricing.json'
    if (-not (Test-Path $pricingJsonPath)) { return [pscustomobject]@{ price = $null; status = 'unknown' } }
    $pricingData = Read-JsonSafe $pricingJsonPath $null
    $entry = Get-PropertyValue $pricingData.tours $TourId $null
    if ($null -eq $entry) { return [pscustomobject]@{ price = $null; status = 'not_in_pricing_matrix' } }
    $options = @(Get-PropertyValue $entry 'options' @())
    $activeOpts = @($options | Where-Object { (Get-PropertyValue $_ 'estimator_status' '') -eq 'active' })
    if ($activeOpts.Count -eq 0) {
        $hasManualQuote = @($options | Where-Object { (Get-PropertyValue $_ 'estimator_status' '') -eq 'manual_quote' }).Count -gt 0
        return [pscustomobject]@{ price = $null; status = if ($hasManualQuote) { 'manual_quote' } else { 'unknown' } }
    }
    $minVal = $null
    foreach ($opt in $activeOpts) {
        foreach ($tierField in @('pp_2', 'pp_3', 'pp_4plus')) {
            $tierVal = Get-PropertyValue $opt $tierField $null
            if ($null -ne $tierVal -and ($null -eq $minVal -or [double]$tierVal -lt $minVal)) { $minVal = [double]$tierVal }
        }
    }
    return [pscustomobject]@{ price = $minVal; status = 'active' }
}

function Convert-ToArray {
    param($Value, [string]$ContainerProperty = '')
    if ($null -eq $Value) { return @() }
    if ($ContainerProperty) {
        $contained = Get-PropertyValue $Value $ContainerProperty $null
        if ($null -ne $contained) { return @($contained) }
    }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Get-FileCount {
    param([string]$Path, [string]$Filter = '*')
    if (-not (Test-Path $Path)) { return 0 }
    return @(Get-ChildItem -Path $Path -File -Filter $Filter -ErrorAction SilentlyContinue).Count
}

function Get-LatestBuild {
    $history = Read-JsonSafe (Join-Path $root 'reports\build-history.json') @()
    $items = @(Convert-ToArray $history 'builds')
    if ($items.Count -gt 0) { return $items[-1] }

    $logs = @(Get-ChildItem (Join-Path $root 'reports') -File -Filter 'build-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($logs.Count -gt 0) {
        return [pscustomobject]@{
            status = 'Successful'
            timestamp = $logs[0].LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            duration = 'N/A'
            errors = 0
            warnings = 0
        }
    }
    return $null
}

function Write-AnalyticsEvent {
    param($Payload)
    $analyticsDir = Join-Path $root 'analytics'
    New-Item -ItemType Directory -Force -Path $analyticsDir | Out-Null
    $slug = [string](Get-PropertyValue $Payload 'slug' '')
    if ([string]::IsNullOrWhiteSpace($slug)) { return [pscustomobject]@{ ok=$false; error='Falta el slug' } }
    $validTypes = @('view','whatsapp_click','tour_click')
    $type = [string](Get-PropertyValue $Payload 'type' 'view')
    if ($type -notin $validTypes) { $type = 'view' }
    $event = [pscustomobject][ordered]@{
        slug       = $slug
        ts         = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        type       = $type
        country    = [string](Get-PropertyValue $Payload 'country' 'XX')
        device     = [string](Get-PropertyValue $Payload 'device' 'desktop')
        source     = [string](Get-PropertyValue $Payload 'source' 'direct')
        visitor_id = [string](Get-PropertyValue $Payload 'visitor_id' '')
    }
    $eventsPath = Join-Path $analyticsDir 'article-events.jsonl'
    $line = $event | ConvertTo-Json -Compress
    [System.IO.File]::AppendAllText($eventsPath, $line + "`n", [System.Text.Encoding]::UTF8)
    return [pscustomobject]@{ ok=$true }
}

function Get-AnalyticsSummary {
    $analyticsDir = Join-Path $root 'analytics'
    $eventsPath = Join-Path $analyticsDir 'article-events.jsonl'
    $summary = @{}
    if (-not (Test-Path $eventsPath)) { return [pscustomobject]$summary }
    $now   = [DateTime]::UtcNow
    $cut7  = $now.AddDays(-7)
    $cut30 = $now.AddDays(-30)
    foreach ($ln in [System.IO.File]::ReadAllLines($eventsPath, [System.Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        try { $e = $ln | ConvertFrom-Json } catch { continue }
        $slug = [string](Get-PropertyValue $e 'slug' '')
        if ([string]::IsNullOrWhiteSpace($slug)) { continue }
        if (-not $summary.ContainsKey($slug)) {
            $summary[$slug] = @{
                views=0; visitor_set=[System.Collections.Generic.HashSet[string]]::new()
                countries=@{}; devices=@{}; sources=@{}
                whatsapp_clicks=0; tour_clicks=0; views_7d=0; views_30d=0; last_view=''
            }
        }
        $s    = $summary[$slug]
        $type = [string](Get-PropertyValue $e 'type' 'view')
        $ts   = [string](Get-PropertyValue $e 'ts' '')
        if ($type -eq 'view') {
            $s.views++
            $vid = [string](Get-PropertyValue $e 'visitor_id' '')
            if (-not [string]::IsNullOrWhiteSpace($vid)) { [void]$s.visitor_set.Add($vid) }
            if (-not [string]::IsNullOrWhiteSpace($ts)) {
                try {
                    $et = [DateTime]::Parse($ts,[System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
                    if ($et -gt $cut7)  { $s.views_7d++ }
                    if ($et -gt $cut30) { $s.views_30d++ }
                    if ([string]::IsNullOrWhiteSpace($s.last_view) -or $ts -gt $s.last_view) { $s.last_view = $ts }
                } catch {}
            }
            $c=[string](Get-PropertyValue $e 'country' 'XX'); if (-not $s.countries.ContainsKey($c)){$s.countries[$c]=0}; $s.countries[$c]++
            $d=[string](Get-PropertyValue $e 'device'  'desktop'); if (-not $s.devices.ContainsKey($d)){$s.devices[$d]=0}; $s.devices[$d]++
            $r=[string](Get-PropertyValue $e 'source'  'direct'); if (-not $s.sources.ContainsKey($r)){$s.sources[$r]=0}; $s.sources[$r]++
        }
        elseif ($type -eq 'whatsapp_click') { $s.whatsapp_clicks++ }
        elseif ($type -eq 'tour_click')     { $s.tour_clicks++ }
    }
    $result = @{}
    foreach ($slug in $summary.Keys) {
        $s = $summary[$slug]
        $topC = if ($s.countries.Count -gt 0) { ($s.countries.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key } else { '' }
        $result[$slug] = [pscustomobject][ordered]@{
            views=$s.views; unique_visitors=$s.visitor_set.Count
            countries=[pscustomobject]$s.countries; devices=[pscustomobject]$s.devices; sources=[pscustomobject]$s.sources
            whatsapp_clicks=$s.whatsapp_clicks; tour_clicks=$s.tour_clicks
            views_7d=$s.views_7d; views_30d=$s.views_30d; last_view=$s.last_view; top_country=$topC
        }
    }
    return [pscustomobject]$result
}

function Get-ControlState {
    $blogsRaw = Read-JsonSafe (Join-Path $root 'blog-data.json') @()
    $blogs = @(Convert-ToArray $blogsRaw 'articles')

    $hotelDir = Join-Path $root 'knowledge\master\hotels'
    $tourDir = Join-Path $root 'knowledge\tours'
    $destinationDir = Join-Path $root 'knowledge\destinations'
    $draftDir = Join-Path $root 'knowledge\content\drafts'
    $opportunityPath = Join-Path $root 'knowledge\content\opportunities\content-opportunities.json'

    $hotels = @()
    if (Test-Path $hotelDir) {
        foreach ($file in Get-ChildItem $hotelDir -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' } | Sort-Object Name) {
            $item = Read-JsonSafe $file.FullName $null
            if ($item) {
                $identity = Get-PropertyValue $item 'identity' $null
                $location = Get-PropertyValue $item 'location' $null
                $workflow = Get-PropertyValue $item 'workflow' $null
                $hotelId = [string](Get-PropertyValue $identity 'id' ([IO.Path]::GetFileNameWithoutExtension($file.Name)))
                $quality = Get-HotelQualityReport $hotelId
                $hotels += [pscustomobject]@{
                    id = $hotelId
                    name = [string](Get-PropertyValue $identity 'display_name' (Get-PropertyValue $identity 'official_name' $file.BaseName))
                    category = [string](Get-PropertyValue $identity 'category' 'Experience Guide')
                    location = [string](Get-PropertyValue $location 'location_label' '')
                    workflow = [string](Get-PropertyValue $workflow 'status' 'review')
                    page = "../hotels/$($file.BaseName).html"
                    quality = if ($quality) { [int](Get-PropertyValue $quality 'overall' 0) } else { $null }
                }
            }
        }
    }

    $tours = @()
    if (Test-Path $tourDir) {
        foreach ($file in Get-ChildItem $tourDir -Filter '*.json' -File | Sort-Object Name) {
            $item = Read-JsonSafe $file.FullName $null
            if ($item) {
                $intel = Get-PropertyValue $item 'intelligence' $null
                $tours += [pscustomobject]@{
                    id = [string](Get-PropertyValue $item 'id' $file.BaseName)
                    name = [string](Get-PropertyValue $item 'name' $file.BaseName)
                    category = [string](Get-PropertyValue $intel 'primary_category' (Get-PropertyValue $item 'category' 'Experience'))
                    energy = [string](Get-PropertyValue $intel 'energy_level' 'N/A')
                    priority = [int](Get-PropertyValue $intel 'recommendation_priority' 0)
                    status = [string](Get-PropertyValue $item 'status' 'active')
                    page = [string](Get-PropertyValue $item 'page_url' '')
                }
            }
        }
    }

    $destinations = @()
    if (Test-Path $destinationDir) {
        foreach ($file in Get-ChildItem $destinationDir -Filter '*.json' -File | Sort-Object Name) {
            $item = Read-JsonSafe $file.FullName $null
            if ($item) {
                $destinations += [pscustomobject]@{
                    id = [string](Get-PropertyValue $item 'id' $file.BaseName)
                    name = [string](Get-PropertyValue $item 'name' $file.BaseName)
                    province = [string](Get-PropertyValue $item 'province' '')
                    page = "../destinations/$($file.BaseName).html"
                }
            }
        }
    }

    $drafts = @()
    if (Test-Path $draftDir) {
        foreach ($file in Get-ChildItem $draftDir -Filter '*.json' -File | Sort-Object LastWriteTime -Descending) {
            $item = Read-JsonSafe $file.FullName $null
            if ($item) {
                $drafts += [pscustomobject]@{
                    slug = [string](Get-PropertyValue $item 'slug' $file.BaseName)
                    title = [string](Get-PropertyValue $item 'title' $file.BaseName)
                    status = [string](Get-PropertyValue $item 'status' 'draft')
                    modified = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                }
            }
        }
    }

    $opportunityData = Read-JsonSafe $opportunityPath $null
    $opportunities = if ($opportunityData) { @($opportunityData.opportunities) } else { @() }
    $questions = Get-Questions
    $questionsPending = @($questions | Where-Object { $_.status -ne 'published' }).Count
    $questionsPublished = @($questions | Where-Object { $_.status -eq 'published' }).Count

    $lastBuild = Get-LatestBuild
    $buildStatus = if ($lastBuild) { [string](Get-PropertyValue $lastBuild 'status' 'Unknown') } else { 'Unknown' }
    $buildErrors = if ($lastBuild) { [int](Get-PropertyValue $lastBuild 'errors' 0) } else { 0 }
    $buildWarnings = if ($lastBuild) { [int](Get-PropertyValue $lastBuild 'warnings' 0) } else { 0 }
    $buildDate = if ($lastBuild) { [string](Get-PropertyValue $lastBuild 'timestamp' (Get-PropertyValue $lastBuild 'date' '')) } else { '' }

    return [pscustomobject][ordered]@{
        generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        platform = [pscustomobject][ordered]@{
            hotels = $hotels.Count
            tours = $tours.Count
            destinations = $destinations.Count
            articles = $blogs.Count
            drafts = $drafts.Count
            opportunities = $opportunities.Count
            questions_pending = $questionsPending
            questions_published = $questionsPublished
            build_status = $buildStatus
            build_errors = $buildErrors
            build_warnings = $buildWarnings
            build_date = $buildDate
            production_ready = ($buildErrors -eq 0)
        }
        hotels = $hotels
        tours = $tours
        destinations = $destinations
        drafts = $drafts
        opportunities = $opportunities
        articles = @($blogs | ForEach-Object {
            [pscustomobject]@{
                id = Get-PropertyValue $_ 'id' 0
                slug = [string](Get-PropertyValue $_ 'slug' '')
                title = [string](Get-PropertyValue $_ 'title' '')
                status = [string](Get-PropertyValue $_ 'status' 'published')
                category = [string](Get-PropertyValue $_ 'category' '')
            }
        })
    }
}

function Send-Json {
    param($Context, $Object, [int]$StatusCode = 200)
    $json = $Object | ConvertTo-Json -Depth 30
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = 'application/json; charset=utf-8'
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.OutputStream.Close()
}

function Send-Text {
    param($Context, [string]$Text, [string]$ContentType = 'text/plain; charset=utf-8', [int]$StatusCode = 200)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = $ContentType
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.OutputStream.Close()
}

function Read-RequestJson {
    param($Request)
    # Always decode as UTF-8, regardless of $Request.ContentEncoding: our own
    # client always sends UTF-8 JSON bodies (browsers encode fetch() bodies as
    # UTF-8 unconditionally), but HttpListenerRequest.ContentEncoding silently
    # falls back to the system ANSI codepage (not null/absent, an *actual*
    # wrong encoding) whenever the Content-Type header omits a charset -- which
    # ours always does -- so trusting it here mis-decodes every accented
    # character in every request body.
    $reader = New-Object IO.StreamReader($Request.InputStream, [System.Text.Encoding]::UTF8)
    try { $raw = $reader.ReadToEnd() } finally { $reader.Close() }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json
}

function Validate-Article {
    param($Article)

    $errors = @()
    $warnings = @()
    $improvements = New-Object 'System.Collections.Generic.List[string]'
    $checks = New-Object 'System.Collections.Generic.List[object]'
    $scoreRef = [ref]0
    $maxRef = [ref]0

    function Add-QualityCheck {
        param(
            [string]$Label,
            [bool]$Passed,
            [int]$Points,
            [string]$Improve
        )

        $maxRef.Value += $Points
        if ($Passed) {
            $scoreRef.Value += $Points
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Improve)) {
            $improvements.Add($Improve)
        }

        $checks.Add([pscustomobject][ordered]@{
            label       = $Label
            passed      = $Passed
            points      = $Points
            improvement = $Improve
        })
    }

    $required = @(
        'slug','title','excerpt','seo_title_pro','seo_description',
        'content_block_1','content_block_2','content_block_3',
        'content_block_faq','cta_url','cta_text'
    )

    foreach ($field in $required) {
        $value = [string](Get-PropertyValue $Article $field '')
        if ([string]::IsNullOrWhiteSpace($value)) {
            $errors += "Falta el campo requerido: $field"
        }
    }

    $title = [string](Get-PropertyValue $Article 'title' '')
    $slug = [string](Get-PropertyValue $Article 'slug' '')
    $excerpt = [string](Get-PropertyValue $Article 'excerpt' '')
    $seoTitle = [string](Get-PropertyValue $Article 'seo_title_pro' '')
    $seoDescription = [string](Get-PropertyValue $Article 'seo_description' '')
    $seoKeywords = [string](Get-PropertyValue $Article 'seo_keywords' '')
    $block1 = [string](Get-PropertyValue $Article 'content_block_1' '')
    $block2 = [string](Get-PropertyValue $Article 'content_block_2' '')
    $block3 = [string](Get-PropertyValue $Article 'content_block_3' '')
    $faq = [string](Get-PropertyValue $Article 'content_block_faq' '')
    $ctaText = [string](Get-PropertyValue $Article 'cta_text' '')
    $ctaUrl = [string](Get-PropertyValue $Article 'cta_url' '')
    $heroImage = [string](Get-PropertyValue $Article 'image_top' '')
    $heroAlt = [string](Get-PropertyValue $Article 'image_top_alt' '')
    $middleImage = [string](Get-PropertyValue $Article 'image_middle' '')
    $middleAlt = [string](Get-PropertyValue $Article 'image_middle_alt' '')
    $bottomImage = [string](Get-PropertyValue $Article 'image_bottom' '')
    $bottomAlt = [string](Get-PropertyValue $Article 'image_bottom_alt' '')
    $travelTip = [string](Get-PropertyValue $Article 'travel_tip' '')
    $quickFacts = @((Get-PropertyValue $Article 'quick_facts' @()))
    $internalLinks = @((Get-PropertyValue $Article 'internal_links' @()))
    $tourIds = @((Get-PropertyValue $Article 'tour_ids' @()))
    $hotelIds = @((Get-PropertyValue $Article 'hotel_ids' @()))
    $destinationIds = @((Get-PropertyValue $Article 'destination_ids' @()))

    Add-QualityCheck 'Título del artículo' (-not [string]::IsNullOrWhiteSpace($title)) 5 'Agrega un título claro al artículo.'
    Add-QualityCheck 'Slug (URL)' (-not [string]::IsNullOrWhiteSpace($slug)) 5 'Agrega un slug corto y descriptivo.'
    Add-QualityCheck 'Extracto' ($excerpt.Length -ge 80) 5 'Amplía el extracto a al menos 80 caracteres.'
    Add-QualityCheck 'Bloques de contenido principales' ((-not [string]::IsNullOrWhiteSpace($block1)) -and (-not [string]::IsNullOrWhiteSpace($block2)) -and (-not [string]::IsNullOrWhiteSpace($block3))) 10 'Completa los tres bloques principales de contenido.'
    Add-QualityCheck 'Sección de preguntas frecuentes' (($faq -match '<h3') -and ($faq.Length -ge 180)) 5 'Agrega preguntas frecuentes útiles.'

    Add-QualityCheck 'Título SEO presente' (-not [string]::IsNullOrWhiteSpace($seoTitle)) 5 'Agrega un título SEO.'
    Add-QualityCheck 'Longitud del título SEO' ($seoTitle.Length -ge 40 -and $seoTitle.Length -le 60 -and $seoTitle -notmatch '\.\.\.$') 5 'Mantén el título SEO entre 40 y 60 caracteres, sin puntos suspensivos de truncado.'
    Add-QualityCheck 'Descripción SEO presente' (-not [string]::IsNullOrWhiteSpace($seoDescription)) 5 'Agrega una descripción SEO.'
    Add-QualityCheck 'Longitud de la descripción SEO' ($seoDescription.Length -ge 120 -and $seoDescription.Length -le 155 -and $seoDescription -notmatch '\.\.\.$') 5 'Mantén la descripción SEO entre 120 y 155 caracteres, sin puntos suspensivos de truncado.'
    $keywordCount = @($seoKeywords -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    Add-QualityCheck 'Palabras clave SEO' ($keywordCount -ge 3) 5 'Agrega al menos tres palabras clave SEO relevantes.'

    Add-QualityCheck 'Foto principal' (-not [string]::IsNullOrWhiteSpace($heroImage)) 5 'Selecciona una foto principal.'
    Add-QualityCheck 'Texto alternativo (foto principal)' (([string]::IsNullOrWhiteSpace($heroImage)) -or (-not [string]::IsNullOrWhiteSpace($heroAlt))) 3 'Agrega texto alternativo a la foto principal.'
    Add-QualityCheck 'Texto alternativo (foto de en medio)' (([string]::IsNullOrWhiteSpace($middleImage)) -or (-not [string]::IsNullOrWhiteSpace($middleAlt))) 3 'Agrega texto alternativo a la foto de en medio.'
    Add-QualityCheck 'Texto alternativo (foto final)' (([string]::IsNullOrWhiteSpace($bottomImage)) -or (-not [string]::IsNullOrWhiteSpace($bottomAlt))) 3 'Agrega texto alternativo a la foto final.'
    $usedImages = @($heroImage,$middleImage,$bottomImage | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    Add-QualityCheck 'Apoyo visual' ($usedImages -ge 1) 6 'Agrega al menos una foto relevante para el artículo.'

    Add-QualityCheck 'Enlaces internos' ($internalLinks.Count -ge 3) 5 'Agrega al menos tres enlaces internos útiles.'
    Add-QualityCheck 'Relaciones con la base de conocimiento' (($tourIds.Count + $hotelIds.Count + $destinationIds.Count) -ge 1) 5 'Relaciona el artículo con al menos un hotel, tour o destino.'
    Add-QualityCheck 'Llamado a la acción (CTA)' ((-not [string]::IsNullOrWhiteSpace($ctaText)) -and (-not [string]::IsNullOrWhiteSpace($ctaUrl))) 5 'Agrega texto y URL para el botón de acción (CTA).'

    $raw = $Article | ConvertTo-Json -Depth 30
    $placeholderPatterns = @('Editorial draft:','Replace this placeholder','Requires editorial','Summarize who should choose','Explain why this topic matters')
    $hasPlaceholders = $false
    foreach ($pattern in $placeholderPatterns) {
        if ($raw -match [regex]::Escape($pattern)) {
            $hasPlaceholders = $true
            $warnings += "Se detectó texto de relleno sin terminar: $pattern"
        }
    }
    Add-QualityCheck 'Contenido editorial completo' (-not $hasPlaceholders) 7 'Reemplaza todos los textos de relleno con contenido final.'
    Add-QualityCheck 'Consejo local de viaje' ((-not [string]::IsNullOrWhiteSpace($travelTip)) -and $travelTip -notmatch 'Replace this placeholder') 3 'Agrega un consejo local específico.'
    Add-QualityCheck 'Quick Facts' ($quickFacts.Count -ge 3) 4 'Agrega al menos 3 Quick Facts.'

    if ($seoTitle.Length -gt 65) { $warnings += 'El título SEO tiene más de 65 caracteres.' }
    if ($seoDescription.Length -gt 160) { $warnings += 'La descripción SEO tiene más de 160 caracteres.' }
    if ($internalLinks.Count -eq 0) { $warnings += 'No se detectaron enlaces internos.' }
    if (-not [string]::IsNullOrWhiteSpace($middleImage) -and [string]::IsNullOrWhiteSpace($middleAlt)) { $warnings += 'A la foto de en medio le falta texto alternativo.' }
    if (-not [string]::IsNullOrWhiteSpace($bottomImage) -and [string]::IsNullOrWhiteSpace($bottomAlt)) { $warnings += 'A la foto final le falta texto alternativo.' }

    $rawPct = if ($maxRef.Value -gt 0) { [Math]::Round(($scoreRef.Value / $maxRef.Value) * 100) } else { 0 }
    $score = [Math]::Min(100, [Math]::Max(0, [int]$rawPct))

    $seenImprovements = @{}
    $uniqueImprovements = @()
    foreach ($imp in $improvements) {
        if (-not $seenImprovements.ContainsKey($imp)) {
            $seenImprovements[$imp] = $true
            $uniqueImprovements += $imp
        }
    }
    $checksArray = @()
    foreach ($c in $checks) { $checksArray += $c }

    $result = [ordered]@{
        valid = ($errors.Count -eq 0)
        quality_score = $score
        ready_for_100 = ($score -eq 100)
        errors = $errors
        warnings = $warnings
        improvements = $uniqueImprovements
        checks = $checksArray
    }
    return New-Object PSObject -Property $result
}
function Save-ArticleDraft {
    param($Article)
    $validation = Validate-Article $Article
    if (-not $validation.valid) { return [pscustomobject]@{ success=$false; validation=$validation } }
    $slug = [string]$Article.slug
    $draftDir = Join-Path $root 'knowledge\content\drafts'
    $backupDir = Join-Path $root 'knowledge\backups\content-drafts'
    New-Item -ItemType Directory -Force -Path $draftDir | Out-Null
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $path = Join-Path $draftDir "$slug.json"
    if (Test-Path $path) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item $path (Join-Path $backupDir "$slug-$stamp.json")
    }
    $json = $Article | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return [pscustomobject]@{ success=$true; path=$path; validation=$validation }
}

function Complete-ArticleMetadata {
    param($Article, $ExistingArticles)
    # Nothing else in the save/publish path fills these in -- an article pasted or
    # built without them (e.g. via the raw-JSON "Cargar" panel) would otherwise
    # publish with a blank byline/date/id, exactly what happened with the
    # 11-month-old article. Only fill what's actually missing; never overwrite a
    # value the user already set.
    if (-not [string](Get-PropertyValue $Article 'id' '')) {
        $nextId = 1
        if (@($ExistingArticles).Count -gt 0) { $nextId = ([int](@($ExistingArticles) | ForEach-Object { [int](Get-PropertyValue $_ 'id' 0) } | Measure-Object -Maximum).Maximum) + 1 }
        $Article | Add-Member -MemberType NoteProperty -Name 'id' -Value $nextId -Force
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue $Article 'date' ''))) {
        $Article | Add-Member -MemberType NoteProperty -Name 'date' -Value ((Get-Date).ToString('MMMM d, yyyy', [System.Globalization.CultureInfo]::GetCultureInfo('en-US'))) -Force
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue $Article 'iso_date' ''))) {
        $Article | Add-Member -MemberType NoteProperty -Name 'iso_date' -Value ((Get-Date).ToString('yyyy-MM-ddT00:00:00Z')) -Force
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue $Article 'readTime' ''))) {
        $wordish = ([string](Get-PropertyValue $Article 'content_block_1' '')).Length + ([string](Get-PropertyValue $Article 'content_block_2' '')).Length + ([string](Get-PropertyValue $Article 'content_block_3' '')).Length
        $Article | Add-Member -MemberType NoteProperty -Name 'readTime' -Value ([string][Math]::Max(3, [Math]::Round($wordish / 1200))) -Force
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue $Article 'author_name' ''))) {
        $Article | Add-Member -MemberType NoteProperty -Name 'author_name' -Value 'Wild Papagayo Team' -Force
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue $Article 'author_badge' ''))) {
        $Article | Add-Member -MemberType NoteProperty -Name 'author_badge' -Value 'Costa Rica Local Experts' -Force
    }
    return $Article
}

function Publish-Article {
    param($Article, [bool]$RunGenerator)

    $blogPath = Join-Path $root 'blog-data.json'
    $backupDir = Join-Path $root 'knowledge\backups\blog-data'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $articles = @()
    if (Test-Path $blogPath) {
        $articles = Read-JsonSafe $blogPath @()
        if ($null -eq $articles) { $articles = @() }
        $articles = @($articles)
    }
    $Article = Complete-ArticleMetadata $Article $articles

    $saved = Save-ArticleDraft $Article
    if (-not $saved.success) { return $saved }

    if (Test-Path $blogPath) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item $blogPath (Join-Path $backupDir "blog-data-$stamp.json")
    }
    $slug = [string]$Article.slug
    $Article | Add-Member -MemberType NoteProperty -Name 'status' -Value 'published' -Force
    $articles = @($articles | Where-Object { [string]$_.slug -ne $slug }) + @($Article)
    $json = $articles | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($blogPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    $generatorOutput = ''
    if ($RunGenerator) {
        $script = Join-Path $root 'blog-generator.ps1'
        if (Test-Path $script) {
            $generatorOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script 2>&1 | Out-String)
        }
    }
    return [pscustomobject]@{ success=$true; blog_path=$blogPath; generator_output=$generatorOutput; validation=$saved.validation }
}

function Run-AllowedCommand {
    param([string]$Name)
    $map = @{
        'build' = 'wild-engine.ps1'
        'validate-hotels' = 'hotel-engine-validator.ps1'
        'validate-content' = 'content-link-validator.ps1'
        'content-opportunities' = 'content-opportunity-engine.ps1'
        'tour-intelligence' = 'tour-intelligence-builder.ps1'
        'tour-rankings' = 'tour-ranking-engine.ps1'
        'blog-engine' = 'blog-generator.ps1'
        'hotel-engine' = 'hotel-generator.ps1'
        'month-engine' = 'month-generator.ps1'
        'category-engine' = 'category-generator.ps1'
        'tour-finder' = 'tool-finder-generator.ps1'
        'destination-finder' = 'destination-finder-generator.ps1'
        'experience-profiles' = 'experience-profile-generator.ps1'
        'assistant-knowledge' = 'assistant-knowledge-generator.ps1'
        'recommendation-engine' = 'recommendation-engine.ps1'
        'destination-health' = 'destination-health-report.ps1'
        'restaurant-finder' = 'restaurant-finder.ps1'
        'hotel-reviews-finder' = 'hotel-reviews-finder.ps1'
        'hotel-transfer-time-finder' = 'hotel-transfer-time-finder.ps1'
        'hotel-photo-finder' = 'hotel-photo-finder.ps1'
        'hotel-address-finder' = 'hotel-address-finder.ps1'
        'hotel-legacy-publish' = 'hotel-legacy-publish-all.ps1'
        'hotel-experience-scores' = 'hotel-experience-scorer.ps1'
        'destination-experience-scores' = 'destination-experience-scorer.ps1'
        'hotels-index' = 'hotels-index-generator.ps1'
        'deploy-package' = 'deploy-package.ps1'
        'tour-engine' = 'tour-generator.ps1'
    }
    if (-not $map.ContainsKey($Name)) { throw "Unknown command: $Name" }
    $scriptPath = Join-Path $root $map[$Name]
    if (-not (Test-Path $scriptPath)) { throw "Script not found: $scriptPath" }

    $cmdArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath)
    if ($Name -eq 'content-opportunities') { $cmdArgs += @('-Top','50') }
    if ($Name -eq 'tour-intelligence') { $cmdArgs += @('-All') }
    if ($Name -eq 'tour-rankings') { $cmdArgs += @('-All','-Top','10','-Force') }

    $output = (& powershell.exe @cmdArgs 2>&1 | Out-String)
    return [pscustomobject]@{ success=$true; command=$Name; output=$output }
}

function Invoke-WildScript {
    param([string]$ScriptName, [string[]]$ScriptArgs = @())
    $scriptPath = Join-Path $root $ScriptName
    if (-not (Test-Path $scriptPath)) { throw "Script not found: $scriptPath" }
    $cmdArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath) + $ScriptArgs
    $exitCode = 0
    $output = (& powershell.exe @cmdArgs 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{ ok = ($exitCode -eq 0); output = $output }
}

function New-Hotel {
    param($Payload)
    $name = [string](Get-PropertyValue $Payload 'name' '')
    if ([string]::IsNullOrWhiteSpace($name)) { return [pscustomobject]@{ success=$false; error='El nombre del hotel es obligatorio.' } }
    $step = Invoke-WildScript 'hotel-create.ps1' @('-HotelName', $name)
    if (-not $step.ok) { return [pscustomobject]@{ success=$false; error=$step.output } }
    if ($step.output -notmatch '"id"\s*:\s*"([^"]+)"') { return [pscustomobject]@{ success=$false; error='No se pudo leer el id del nuevo hotel.'; output=$step.output } }
    $id = $Matches[1]
    return [pscustomobject]@{ success=$true; id=$id; output=$step.output }
}

function New-HotelFromUrl {
    param($Payload)
    $url = [string](Get-PropertyValue $Payload 'url' '')
    if ([string]::IsNullOrWhiteSpace($url)) { return [pscustomobject]@{ success=$false; error='La URL es obligatoria.' } }
    $name = [string](Get-PropertyValue $Payload 'name' '')
    $scriptArgs = @('-Url', $url)
    if (-not [string]::IsNullOrWhiteSpace($name)) { $scriptArgs += @('-HotelName', $name) }
    $step = Invoke-WildScript 'hotel-import-url.ps1' $scriptArgs
    if (-not $step.ok) { return [pscustomobject]@{ success=$false; error=$step.output } }
    if ($step.output -notmatch '"id"\s*:\s*"([^"]+)"') { return [pscustomobject]@{ success=$false; error='No se pudo leer el id del nuevo hotel.'; output=$step.output } }
    $id = $Matches[1]
    return [pscustomobject]@{ success=$true; id=$id; output=$step.output }
}

function New-DestinationFromUrl {
    param($Payload)
    $id = [string](Get-PropertyValue $Payload 'id' '')
    $url = [string](Get-PropertyValue $Payload 'url' '')
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($url)) { return [pscustomobject]@{ success=$false; error='Se necesitan el id del destino y una URL.' } }
    $step = Invoke-WildScript 'destination-import-url.ps1' @('-DestinationId', $id, '-Url', $url)
    if (-not $step.ok) { return [pscustomobject]@{ success=$false; error=$step.output } }
    return [pscustomobject]@{ success=$true; output=$step.output }
}

function Get-QuestionsPath { return (Join-Path $root 'questions\questions.json') }

function Get-Questions {
    $qPath = Get-QuestionsPath
    $list = Read-JsonSafe $qPath @()
    return @($list)
}

function New-QuestionAnalysis {
    param($Payload)
    $text = [string](Get-PropertyValue $Payload 'text' '')
    if ([string]::IsNullOrWhiteSpace($text)) { return [pscustomobject]@{ success=$false; error='El texto de la pregunta es obligatorio.' } }
    $source = [string](Get-PropertyValue $Payload 'source' 'facebook')
    $step = Invoke-WildScript 'question-analyze.ps1' @('-QuestionText', $text, '-Source', $source)
    if (-not $step.ok) { return [pscustomobject]@{ success=$false; error=$step.output } }
    $lines = @($step.output -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') })
    if ($lines.Count -eq 0) { return [pscustomobject]@{ success=$false; error='No se pudo interpretar el resultado del análisis.'; output=$step.output } }
    try {
        $analysis = $lines[-1] | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{ success=$false; error='El resultado del análisis no es un JSON válido.'; output=$step.output }
    }
    return [pscustomobject]@{ success=$true; analysis=$analysis }
}

function New-ArticleAutoDraft {
    param($Article)
    $title = [string](Get-PropertyValue $Article 'title' '')
    if ([string]::IsNullOrWhiteSpace($title)) { return [pscustomobject]@{ success=$false; error='El artículo necesita un título antes de redactarlo.' } }

    $tempDir = Join-Path $root 'knowledge\backups\auto-draft-temp'
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $tempPath = Join-Path $tempDir "$([guid]::NewGuid()).json"
    $resultPath = "$tempPath.result.json"
    try {
        $json = $Article | ConvertTo-Json -Depth 30
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        $step = Invoke-WildScript 'article-auto-draft.ps1' @('-ArticleJsonPath', $tempPath)
        if (-not $step.ok) { return [pscustomobject]@{ success=$false; error=$step.output } }
        if (-not (Test-Path $resultPath)) { return [pscustomobject]@{ success=$false; error='No se generó el archivo de resultado de Claude.'; output=$step.output } }
        $updated = Read-JsonSafe $resultPath $null
        if (-not $updated) { return [pscustomobject]@{ success=$false; error='El resultado de Claude no es un JSON válido.'; output=$step.output } }
        return [pscustomobject]@{ success=$true; article=$updated }
    } finally {
        if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $resultPath) { Remove-Item $resultPath -Force -ErrorAction SilentlyContinue }
    }
}

function Save-Question {
    param($Payload)
    $questionText = [string](Get-PropertyValue $Payload 'question' '')
    if ([string]::IsNullOrWhiteSpace($questionText)) { return [pscustomobject]@{ success=$false; error='El texto de la pregunta es obligatorio.' } }
    $qPath = Get-QuestionsPath
    $questions = Read-JsonSafe $qPath @()
    if ($null -eq $questions) { $questions = @() }
    $questions = @($questions)

    $slugSource = [string](Get-PropertyValue $Payload 'suggested_slug' '')
    if ([string]::IsNullOrWhiteSpace($slugSource)) { $slugSource = $questionText }
    # Transliterate accented letters before stripping non-alphanumeric chars, or
    # e.g. "Rio" collapses to the mangled "r-o" instead of "rio" (see New-Slug in
    # question-article-writer.ps1 for the full explanation -- same bug, same fix).
    $accentMap = @{ 'á'='a';'é'='e';'í'='i';'ó'='o';'ú'='u';'ñ'='n';'ü'='u' }
    $slugNormalized = $slugSource.ToLowerInvariant()
    foreach ($accentKey in $accentMap.Keys) { $slugNormalized = $slugNormalized.Replace($accentKey, $accentMap[$accentKey]) }
    $slug = $slugNormalized -replace '[^a-z0-9]+','-'
    $slug = $slug.Trim('-')
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0,60).Trim('-') }
    $id = "q-$slug"
    $suffix = 1
    $baseId = $id
    while (@($questions | Where-Object { $_.id -eq $id }).Count -gt 0) { $suffix++; $id = "$baseId-$suffix" }

    $record = [ordered]@{
        id = $id
        question = $questionText
        working_title = [string](Get-PropertyValue $Payload 'working_title' '')
        source = [string](Get-PropertyValue $Payload 'source' 'facebook')
        source_note = [string](Get-PropertyValue $Payload 'source_note' '')
        intent = [string](Get-PropertyValue $Payload 'intent' '')
        content_type = [string](Get-PropertyValue $Payload 'content_type' '')
        priority = [int](Get-PropertyValue $Payload 'priority' 50)
        seo_potential = [int](Get-PropertyValue $Payload 'seo_potential' 0)
        competition = [string](Get-PropertyValue $Payload 'competition' '')
        commercial_intent = [string](Get-PropertyValue $Payload 'commercial_intent' '')
        status = 'pending'
        article_slug = ''
        destination_ids = @(Get-PropertyValue $Payload 'destination_ids' @())
        hotel_ids = @(Get-PropertyValue $Payload 'hotel_ids' @())
        tour_ids = @(Get-PropertyValue $Payload 'tour_ids' @())
        activity_ids = @(Get-PropertyValue $Payload 'activity_ids' @())
        season_ids = @(Get-PropertyValue $Payload 'season_ids' @())
        traveler_profile_ids = @(Get-PropertyValue $Payload 'traveler_profile_ids' @())
        transportation_ids = @(Get-PropertyValue $Payload 'transportation_ids' @())
        business_goal = [string](Get-PropertyValue $Payload 'business_goal' '')
        notes = [string](Get-PropertyValue $Payload 'notes' '')
    }

    $updated = @($questions) + [pscustomobject]$record
    $json = $updated | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($qPath, $json, [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ success=$true; id=$id }
}

function Update-Question {
    param($Payload)
    $id = [string](Get-PropertyValue $Payload 'id' '')
    if ([string]::IsNullOrWhiteSpace($id)) { return [pscustomobject]@{ success=$false; error='Falta el id de la pregunta.' } }
    $qPath = Get-QuestionsPath
    $questions = @(Read-JsonSafe $qPath @())
    $match = $questions | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $match) { return [pscustomobject]@{ success=$false; error="Pregunta no encontrada: $id" } }

    $match.question = [string](Get-PropertyValue $Payload 'question' $match.question)
    $match.working_title = [string](Get-PropertyValue $Payload 'working_title' $match.working_title)
    $match.source = [string](Get-PropertyValue $Payload 'source' $match.source)
    $match.priority = [int](Get-PropertyValue $Payload 'priority' $match.priority)
    $destinationIds = Get-PropertyValue $Payload 'destination_ids' $null
    if ($null -ne $destinationIds) { $match.destination_ids = @(@($destinationIds) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ } | ForEach-Object { $_.Trim() }) }
    $hotelIds = Get-PropertyValue $Payload 'hotel_ids' $null
    if ($null -ne $hotelIds) { $match.hotel_ids = @(@($hotelIds) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ } | ForEach-Object { $_.Trim() }) }

    $json = $questions | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($qPath, $json, [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ success=$true; id=$id }
}

function Publish-Question {
    param($Payload)
    $id = [string](Get-PropertyValue $Payload 'id' '')
    if ([string]::IsNullOrWhiteSpace($id)) { return [pscustomobject]@{ success=$false; error='Falta el id de la pregunta.' } }
    $step = Invoke-WildScript 'question-article-writer.ps1' @('-QuestionId', $id)
    if (-not $step.ok) { return [pscustomobject]@{ success=$false; error=$step.output } }
    $genStep = Invoke-WildScript 'blog-generator.ps1' @()
    $valStep = Invoke-WildScript 'content-link-validator.ps1' @()
    return [pscustomobject]@{ success=$true; writer_output=$step.output; generator_output=$genStep.output; validation_output=$valStep.output }
}

function Get-TourDetail {
    param([string]$TourId)
    $tourPath = Join-Path $root "knowledge\tours\$TourId.json"
    if (-not (Test-Path $tourPath)) { return $null }
    $t = Read-JsonSafe $tourPath $null
    if (-not $t) { return $null }
    # The real tour page (tour-generator.ps1) is driven by the rich `page_content`
    # fields extracted from the original hand-crafted pages, not the older simple
    # fields below them -- read/write page_content so the editor actually affects
    # the live page instead of silently updating fields the generator ignores.
    $pc = Get-PropertyValue $t 'page_content' $null
    $qs = Get-PropertyValue $pc 'quick_stats' $null
    $pricingTiers = Get-PropertyValue $pc 'pricing_tiers' $null
    $guideOnly = Get-PropertyValue $pricingTiers 'guide_only' $null
    $firstOption = (Get-PropertyValue $pricingTiers 'options' @()) | Select-Object -First 1
    $canonical = Get-CanonicalTourFromPrice -TourId $TourId
    return [pscustomobject]@{
        id = $TourId
        name = [string](Get-PropertyValue $t 'name' $TourId)
        short_description = [string](Get-PropertyValue $t 'short_description' '')
        hero_image = [string](Get-PropertyValue $t 'hero_image' '')
        hero_image_alt = [string](Get-PropertyValue $t 'hero_image_alt' '')
        difficulty = [string](Get-PropertyValue $qs 'difficulty' (Get-PropertyValue $t 'difficulty' ''))
        duration_label = [string](Get-PropertyValue $qs 'duration' (Get-PropertyValue $t 'duration_label' ''))
        included = @(Get-PropertyValue $pc 'everything_included' @())
        what_to_bring = @(Get-PropertyValue $pc 'what_to_pack' @())
        # Read-only -- the real public tour price, sourced from
        # tour-pricing.json (the Excel-derived commercial matrix). Never
        # editable here; edit the Excel and run excel-to-pricing.js.
        canonical_from_price = $canonical.price
        canonical_status = $canonical.status
        # "Precio Desde" below is specifically the Guide Only / self-drive
        # sub-product price (page_content.pricing_tiers.guide_only), a
        # different product from the main canonical price above -- it has
        # no entry in tour-pricing.json and is edited here on purpose.
        from_price = [string](Get-PropertyValue $guideOnly 'price' '')
        currency = 'USD'
        pricing_note = [string](Get-PropertyValue $firstOption 'note' '')
    }
}

function Update-TourFields {
    param($Payload)
    $id = [string](Get-PropertyValue $Payload 'id' '')
    if ([string]::IsNullOrWhiteSpace($id)) { return [pscustomobject]@{ success=$false; error='Falta el id del tour.' } }
    $tourPath = Join-Path $root "knowledge\tours\$id.json"
    if (-not (Test-Path $tourPath)) { return [pscustomobject]@{ success=$false; error="Tour no encontrado: $id" } }
    $t = Read-JsonSafe $tourPath $null
    if (-not $t) { return [pscustomobject]@{ success=$false; error='No se pudo leer el registro del tour.' } }

    $t.short_description = [string](Get-PropertyValue $Payload 'short_description' $t.short_description)
    $heroImage = Get-PropertyValue $Payload 'hero_image' $null
    if ($null -ne $heroImage -and -not [string]::IsNullOrWhiteSpace([string]$heroImage)) {
        $t.hero_image = [string]$heroImage
        $t.hero_image_alt = [string](Get-PropertyValue $Payload 'hero_image_alt' $t.hero_image_alt)
    }

    # The real tour page (tour-generator.ps1) is driven by page_content, not the
    # older simple fields -- write to page_content so edits actually reach the
    # live page. See Get-TourDetail for the matching read-side fix.
    if (-not $t.page_content) { $t | Add-Member -MemberType NoteProperty -Name 'page_content' -Value ([pscustomobject]@{}) -Force }
    $pc = $t.page_content

    if (-not $pc.quick_stats) { $pc | Add-Member -MemberType NoteProperty -Name 'quick_stats' -Value ([pscustomobject]@{}) -Force }
    $difficulty = Get-PropertyValue $Payload 'difficulty' $null
    if ($null -ne $difficulty) {
        $pc.quick_stats | Add-Member -MemberType NoteProperty -Name 'difficulty' -Value ([string]$difficulty) -Force
        $t.difficulty = [string]$difficulty
    }
    $durationLabel = Get-PropertyValue $Payload 'duration_label' $null
    if ($null -ne $durationLabel) {
        $pc.quick_stats | Add-Member -MemberType NoteProperty -Name 'duration' -Value ([string]$durationLabel) -Force
        $t.duration_label = [string]$durationLabel
    }

    $included = Get-PropertyValue $Payload 'included' $null
    if ($null -ne $included) {
        $includedArr = @(@($included) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ })
        $pc | Add-Member -MemberType NoteProperty -Name 'everything_included' -Value $includedArr -Force
        $t.included = $includedArr
    }
    $whatToBring = Get-PropertyValue $Payload 'what_to_bring' $null
    if ($null -ne $whatToBring) {
        $whatToBringArr = @(@($whatToBring) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ })
        $pc | Add-Member -MemberType NoteProperty -Name 'what_to_pack' -Value $whatToBringArr -Force
        $t.what_to_bring = $whatToBringArr
    }

    if (-not $pc.pricing_tiers) { $pc | Add-Member -MemberType NoteProperty -Name 'pricing_tiers' -Value ([pscustomobject]@{}) -Force }
    if (-not $pc.pricing_tiers.guide_only) { $pc.pricing_tiers | Add-Member -MemberType NoteProperty -Name 'guide_only' -Value ([pscustomobject]@{}) -Force }
    if (-not $t.pricing) { $t | Add-Member -MemberType NoteProperty -Name 'pricing' -Value ([pscustomobject]@{}) -Force }
    $fromPrice = Get-PropertyValue $Payload 'from_price' $null
    if ($null -ne $fromPrice -and -not [string]::IsNullOrWhiteSpace([string]$fromPrice)) {
        $pc.pricing_tiers.guide_only | Add-Member -MemberType NoteProperty -Name 'price' -Value ([string]$fromPrice) -Force
        $t.pricing | Add-Member -MemberType NoteProperty -Name 'from_price' -Value ([double][string]$fromPrice) -Force
    }
    $t.pricing | Add-Member -MemberType NoteProperty -Name 'currency' -Value ([string](Get-PropertyValue $Payload 'currency' 'USD')) -Force
    # Write to the same field Get-TourDetail reads the note FROM
    # (page_content.pricing_tiers.options[0].note) -- this used to write to
    # the unrelated, unread pricing.pricing_note instead, so a saved edit
    # never actually showed up the next time the form was reopened.
    $pricingNote = [string](Get-PropertyValue $Payload 'pricing_note' '')
    $firstOptionForNote = (Get-PropertyValue $pc.pricing_tiers 'options' @()) | Select-Object -First 1
    if ($firstOptionForNote) {
        $firstOptionForNote | Add-Member -MemberType NoteProperty -Name 'note' -Value $pricingNote -Force
    }

    $json = $t | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($tourPath, $json, [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ success=$true; id=$id }
}

function Get-CategoriesPath { return (Join-Path $root 'knowledge\categories.json') }

function Get-Categories {
    return @(Read-JsonSafe (Get-CategoriesPath) @())
}

function Save-Category {
    param($Payload)
    $name = [string](Get-PropertyValue $Payload 'name' '')
    $description = [string](Get-PropertyValue $Payload 'description' '')
    if ([string]::IsNullOrWhiteSpace($name)) { return [pscustomobject]@{ success=$false; error='El nombre de la categoría es obligatorio.' } }
    $categories = @(Get-Categories)
    $slug = $name.ToLowerInvariant() -replace '[^a-z0-9]+','-'
    $slug = $slug.Trim('-')
    if (@($categories | Where-Object { $_.slug -eq $slug -or $_.name -eq $name }).Count -gt 0) {
        return [pscustomobject]@{ success=$false; error='Ya existe una categoría con ese nombre.' }
    }
    $categories += [pscustomobject]@{ slug = $slug; name = $name; description = $description }
    $json = $categories | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText((Get-CategoriesPath), $json, [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ success=$true; slug=$slug }
}

function Remove-Category {
    param($Payload)
    $slug = [string](Get-PropertyValue $Payload 'slug' '')
    if ([string]::IsNullOrWhiteSpace($slug)) { return [pscustomobject]@{ success=$false; error='Falta el slug de la categoría.' } }
    $categories = @(Get-Categories)
    $match = $categories | Where-Object { $_.slug -eq $slug } | Select-Object -First 1
    if (-not $match) { return [pscustomobject]@{ success=$false; error='Categoría no encontrada.' } }
    $articles = @(Read-JsonSafe (Join-Path $root 'blog-data.json') @())
    $inUse = @($articles | Where-Object { [string]$_.category -eq [string]$match.name }).Count
    if ($inUse -gt 0) {
        return [pscustomobject]@{ success=$false; error="No se puede eliminar: $inUse artículo(s) todavía usan esta categoría. Cámbialos de categoría primero." }
    }
    $remaining = @($categories | Where-Object { $_.slug -ne $slug })
    $json = $remaining | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText((Get-CategoriesPath), $json, [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ success=$true }
}

function Get-DestinationDetail {
    param([string]$DestinationId)
    $destPath = Join-Path $root "knowledge\destinations\$DestinationId.json"
    if (-not (Test-Path $destPath)) { return $null }
    $d = Read-JsonSafe $destPath $null
    if (-not $d) { return $null }
    return [pscustomobject]@{
        id = $DestinationId
        name = [string](Get-PropertyValue $d 'name' $DestinationId)
        hero_description = [string](Get-PropertyValue $d 'hero_description' '')
        description = [string](Get-PropertyValue $d 'description' '')
        best_season = [string](Get-PropertyValue $d 'best_season' '')
        best_for = @(Get-PropertyValue $d 'best_for' @())
        highlights = @(Get-PropertyValue $d 'highlights' @())
        considerations = @(Get-PropertyValue $d 'considerations' @())
        faq = @(Get-PropertyValue $d 'faq' @())
    }
}

function Update-DestinationFields {
    param($Payload)
    $id = [string](Get-PropertyValue $Payload 'id' '')
    if ([string]::IsNullOrWhiteSpace($id)) { return [pscustomobject]@{ success=$false; error='Falta el id del destino.' } }
    $destPath = Join-Path $root "knowledge\destinations\$id.json"
    if (-not (Test-Path $destPath)) { return [pscustomobject]@{ success=$false; error="Destino no encontrado: $id" } }
    $d = Read-JsonSafe $destPath $null
    if (-not $d) { return [pscustomobject]@{ success=$false; error='No se pudo leer el registro del destino.' } }

    $d.hero_description = [string](Get-PropertyValue $Payload 'hero_description' $d.hero_description)
    $d.description = [string](Get-PropertyValue $Payload 'description' $d.description)
    $d.best_season = [string](Get-PropertyValue $Payload 'best_season' $d.best_season)
    $bestFor = Get-PropertyValue $Payload 'best_for' $null
    if ($null -ne $bestFor) { $d.best_for = @(@($bestFor) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ }) }
    $highlights = Get-PropertyValue $Payload 'highlights' $null
    if ($null -ne $highlights) { $d.highlights = @(@($highlights) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ }) }
    $considerations = Get-PropertyValue $Payload 'considerations' $null
    if ($null -ne $considerations) { $d.considerations = @(@($considerations) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ }) }
    $faq = Get-PropertyValue $Payload 'faq' $null
    if ($null -ne $faq) { $d.faq = @(@($faq) | Where-Object { $_.q }) }

    $json = $d | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($destPath, $json, [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ success=$true; id=$id }
}

function Get-HotelDetail {
    param([string]$HotelId)
    $masterPath = Join-Path $root "knowledge\master\hotels\$HotelId.json"
    if (-not (Test-Path $masterPath)) { return $null }
    $master = Read-JsonSafe $masterPath $null
    if (-not $master) { return $null }
    return [pscustomobject]@{
        id = $HotelId
        name = [string](Get-PropertyValue $master.identity 'display_name' $HotelId)
        brand = [string](Get-PropertyValue $master.identity 'brand' '')
        category = [string](Get-PropertyValue $master.identity 'category' '')
        luxury_level = [string](Get-PropertyValue $master.identity 'luxury_level' '')
        featured_tours = @(Get-PropertyValue $master.recommendations 'featured_tours' @())
        faq = @(Get-PropertyValue $master 'faq' @())
        amenities = @(Get-PropertyValue $master 'amenities' @())
        room_types = @(Get-PropertyValue $master 'room_types' @())
        hero_image = [string](Get-PropertyValue $master.gallery 'hero_image' '')
        hero_image_alt = [string](Get-PropertyValue $master.gallery 'hero_image_alt' '')
        expedia_affiliate_link = [string](Get-PropertyValue $master.booking 'expedia_affiliate_link' '')
    }
}

function Update-HotelFields {
    param($Payload)
    $id = [string](Get-PropertyValue $Payload 'id' '')
    if ([string]::IsNullOrWhiteSpace($id)) { return [pscustomobject]@{ success=$false; error='Falta el id del hotel.' } }
    $masterPath = Join-Path $root "knowledge\master\hotels\$id.json"
    if (-not (Test-Path $masterPath)) { return [pscustomobject]@{ success=$false; error="Hotel not found: $id" } }
    $master = Read-JsonSafe $masterPath $null
    if (-not $master) { return [pscustomobject]@{ success=$false; error='No se pudo leer el registro del hotel.' } }

    $master.identity.brand = [string](Get-PropertyValue $Payload 'brand' $master.identity.brand)
    $master.identity.category = [string](Get-PropertyValue $Payload 'category' $master.identity.category)
    $master.identity.luxury_level = [string](Get-PropertyValue $Payload 'luxury_level' $master.identity.luxury_level)
    $tours = @(Get-PropertyValue $Payload 'featured_tours' $null)
    if ($null -ne (Get-PropertyValue $Payload 'featured_tours' $null)) { $master.recommendations.featured_tours = @($tours | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
    $faq = @(Get-PropertyValue $Payload 'faq' $null)
    if ($null -ne (Get-PropertyValue $Payload 'faq' $null)) {
        $master.faq = @($faq | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue $_ 'q' '')) } | ForEach-Object {
            [pscustomobject]@{ q = [string](Get-PropertyValue $_ 'q' ''); a = [string](Get-PropertyValue $_ 'a' '') }
        })
    }
    if ($null -ne (Get-PropertyValue $Payload 'amenities' $null)) {
        $amenities = @(Get-PropertyValue $Payload 'amenities' @())
        $master | Add-Member -MemberType NoteProperty -Name 'amenities' -Value (@($amenities | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ })) -Force
    }
    if ($null -ne (Get-PropertyValue $Payload 'room_types' $null)) {
        $roomTypes = @(Get-PropertyValue $Payload 'room_types' @())
        $master | Add-Member -MemberType NoteProperty -Name 'room_types' -Value (@($roomTypes | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue $_ 'name' '')) } | ForEach-Object {
            [pscustomobject]@{ name = [string](Get-PropertyValue $_ 'name' ''); description = [string](Get-PropertyValue $_ 'description' '') }
        })) -Force
    }
    $heroImage = Get-PropertyValue $Payload 'hero_image' $null
    if ($null -ne $heroImage -and -not [string]::IsNullOrWhiteSpace([string]$heroImage)) {
        $master.gallery.hero_image = [string]$heroImage
        $master.gallery.hero_image_alt = [string](Get-PropertyValue $Payload 'hero_image_alt' $master.gallery.hero_image_alt)
        $master.gallery.hero_image_status = 'cms_selected'
    }
    if ($null -ne (Get-PropertyValue $Payload 'expedia_affiliate_link' $null)) {
        $expediaLink = [string](Get-PropertyValue $Payload 'expedia_affiliate_link' '')
        if (-not $master.PSObject.Properties['booking']) {
            $master | Add-Member -MemberType NoteProperty -Name 'booking' -Value ([pscustomobject]@{}) -Force
        }
        if ($master.booking.PSObject.Properties['expedia_affiliate_link']) {
            $master.booking.expedia_affiliate_link = $expediaLink
        } else {
            $master.booking | Add-Member -MemberType NoteProperty -Name 'expedia_affiliate_link' -Value $expediaLink -Force
        }
    }

    $json = $master | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($masterPath, $json, [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ success=$true; id=$id }
}

function Publish-Hotel {
    param($Payload)
    $id = [string](Get-PropertyValue $Payload 'id' '')
    if ([string]::IsNullOrWhiteSpace($id)) { return [pscustomobject]@{ success=$false; error='Falta el id del hotel.' } }
    $masterPath = Join-Path $root "knowledge\master\hotels\$id.json"
    if (-not (Test-Path $masterPath)) { return [pscustomobject]@{ success=$false; error="Hotel no encontrado: $id" } }
    $master = Read-JsonSafe $masterPath $null
    if (-not $master) { return [pscustomobject]@{ success=$false; error='No se pudo leer el registro del hotel.' } }

    # Mirrors the manual fix applied by hand to every hotel so far this session --
    # nothing else in the CMS flips a hotel from draft to published, so new hotels
    # stayed stuck on the "draft" badge even once genuinely complete (100% quality).
    $quality = Get-HotelQualityReport $id
    if ($quality -and $quality.ready_to_publish -eq $false) {
        return [pscustomobject]@{ success=$false; error="Calidad actual: $($quality.overall)%. Ejecuta 'Completar con Wild Intelligence' hasta llegar al 90% antes de publicar." }
    }
    if (-not $master.workflow) { $master | Add-Member -MemberType NoteProperty -Name 'workflow' -Value ([pscustomobject]@{}) -Force }
    $master.workflow | Add-Member -MemberType NoteProperty -Name 'status' -Value 'published' -Force

    $json = $master | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($masterPath, $json, [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ success=$true; id=$id }
}

function Get-HotelQualityReport {
    param([string]$HotelId)
    $reportPath = Join-Path $root "reports\intelligence\$HotelId-quality-report.json"
    return Read-JsonSafe $reportPath $null
}

function Complete-HotelIntelligence {
    param([string]$HotelId)
    $masterPath = Join-Path $root "knowledge\master\hotels\$HotelId.json"
    if (-not (Test-Path $masterPath)) { return [pscustomobject]@{ success=$false; error="Hotel not found: $HotelId" } }

    $steps = New-Object 'System.Collections.Generic.List[object]'
    $chain = @(
        @{ label='Hotel Autofill';           script='hotel-autofill.ps1';                args=@('-HotelId',$HotelId) }
        @{ label='Experience Builder';       script='experience-builder.ps1';            args=@('-HotelId',$HotelId) }
        @{ label='Google Reviews';           script='hotel-reviews-finder.ps1';          args=@('-HotelId',$HotelId) }
        @{ label='Wild Intelligence Engine'; script='wild-intelligence-engine.ps1';       args=@('-EntityId',$HotelId,'-PublishLegacy') }
        @{ label='Knowledge Relationships';  script='knowledge-relationship-engine.ps1';  args=@('-EntityType','hotel','-EntityId',$HotelId) }
        @{ label='Hotel Certification';      script='hotel-certification-engine.ps1';     args=@('-EntityId',$HotelId) }
        @{ label='Recommendation Engine';    script='recommendation-engine.ps1';          args=@() }
        @{ label='Hotel Page Generator';     script='hotel-generator.ps1';                args=@() }
        @{ label='Content Opportunities';    script='content-opportunity-engine.ps1';     args=@('-Top','50') }
    )

    $allOk = $true
    foreach ($step in $chain) {
        $result = Invoke-WildScript -ScriptName ([string]$step.script) -ScriptArgs @([string[]]$step.args)
        $steps.Add([pscustomobject]@{ label=$step.label; ok=$result.ok; output=$result.output })
        if (-not $result.ok) { $allOk = $false; break }
    }

    return [pscustomobject]@{
        success = $allOk
        id = $HotelId
        steps = $steps.ToArray()
        quality = Get-HotelQualityReport $HotelId
    }
}


function Get-LinkSuggestions {
    param($Article)

    $title = [string](Get-PropertyValue $Article 'title' '')
    $excerpt = [string](Get-PropertyValue $Article 'excerpt' '')
    $category = [string](Get-PropertyValue $Article 'category' '')
    $selfSlug = [string](Get-PropertyValue $Article 'slug' '')
    $tourIds = @((Get-PropertyValue $Article 'tour_ids' @()))
    $hotelIds = @((Get-PropertyValue $Article 'hotel_ids' @()))
    $destinationIds = @((Get-PropertyValue $Article 'destination_ids' @()))
    $haystack = ("$title $excerpt " + [string](Get-PropertyValue $Article 'content_block_1' '') + ' ' + [string](Get-PropertyValue $Article 'content_block_2' '') + ' ' + [string](Get-PropertyValue $Article 'content_block_3' '')).ToLowerInvariant()

    $candidates = New-Object 'System.Collections.Generic.List[object]'
    $seenUrls = @{}
    function Add-Candidate {
        param([string]$Text, [string]$Url, [string]$Reason)
        if ([string]::IsNullOrWhiteSpace($Url) -or $seenUrls.ContainsKey($Url)) { return }
        $seenUrls[$Url] = $true
        $candidates.Add([pscustomobject]@{ text = $Text; url = $Url; reason = $Reason })
    }

    # 1. Direct structured relationships already tagged on this article.
    foreach ($id in $destinationIds) {
        $d = Read-JsonSafe (Join-Path $root "knowledge\destinations\$id.json") $null
        if ($d) { Add-Candidate "Explore $($d.name)" "../destinations/$id.html" 'destino etiquetado' }
    }
    foreach ($id in $hotelIds) {
        $h = Read-JsonSafe (Join-Path $root "knowledge\hotels\$id.json") $null
        if ($h) { Add-Candidate "$($h.name) Experience Guide" "../hotels/$id.html" 'hotel etiquetado' }
    }
    foreach ($id in $tourIds) {
        $t = Read-JsonSafe (Join-Path $root "knowledge\tours\$id.json") $null
        if ($t -and $t.page_url) { Add-Candidate "$($t.name)" ([string]$t.page_url) 'tour etiquetado' }
    }

    # 2. Name-mention matching -- scan the article's own text for real hotel/destination/tour names.
    $destDir = Join-Path $root 'knowledge\destinations'
    if (Test-Path $destDir) {
        foreach ($f in Get-ChildItem $destDir -Filter '*.json' -File) {
            $d = Read-JsonSafe $f.FullName $null
            if ($d -and $d.name -and $haystack.Contains($d.name.ToLowerInvariant())) {
                Add-Candidate "Explore $($d.name)" "../destinations/$($f.BaseName).html" 'nombre mencionado en el artículo'
            }
        }
    }
    $hotelDir = Join-Path $root 'knowledge\hotels'
    if (Test-Path $hotelDir) {
        foreach ($f in Get-ChildItem $hotelDir -Filter '*.json' -File) {
            $h = Read-JsonSafe $f.FullName $null
            if ($h -and $h.name -and $haystack.Contains($h.name.ToLowerInvariant())) {
                Add-Candidate "$($h.name) Experience Guide" "../hotels/$($f.BaseName).html" 'nombre mencionado en el artículo'
            }
        }
    }

    # 3. Same-category sibling articles -- the most reliable fallback when an article
    # has no tagged entities, since every article always has a category.
    if (-not [string]::IsNullOrWhiteSpace($category)) {
        $blogPath = Join-Path $root 'blog-data.json'
        $articles = @(Read-JsonSafe $blogPath @())
        $siblings = @($articles | Where-Object { [string]$_.category -eq $category -and [string]$_.slug -ne $selfSlug } | Select-Object -First 4)
        foreach ($s in $siblings) {
            Add-Candidate ([string]$s.title) "$([string]$s.slug).html" 'misma categoría'
        }
    }

    return @($candidates | Select-Object -First 8)
}

$mediaImageExtensions = @('.jpg','.jpeg','.png','.webp','.gif')

function Get-MediaMetaPath { return (Join-Path $root 'images\media-meta.json') }

function Get-MediaMeta {
    # Sidecar dict keyed by filename (e.g. "hotel-belmar-hero.jpg") holding only what
    # can't be inferred from the file itself: alt text, caption, and an optional folder tag.
    return (Read-JsonSafe (Get-MediaMetaPath) ([pscustomobject]@{}))
}

function Save-MediaMeta {
    param($Meta)
    $json = $Meta | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText((Get-MediaMetaPath), $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-MediaIndex {
    # Single flat images/ folder is the source of truth -- every real site image shows up
    # here automatically, not just ones uploaded through this panel.
    $imagesRoot = Join-Path $root 'images'
    $meta = Get-MediaMeta
    $items = @()
    foreach ($file in @(Get-ChildItem $imagesRoot -File -ErrorAction SilentlyContinue | Where-Object { $mediaImageExtensions -contains $_.Extension.ToLowerInvariant() })) {
        $entry = $meta.PSObject.Properties[$file.Name]
        $entryVal = if ($entry) { $entry.Value } else { $null }
        $items += [pscustomobject]@{
            id = $file.Name
            file = "images/$($file.Name)"
            name = $file.Name
            folder = [string](Get-PropertyValue $entryVal 'folder' 'general')
            alt = [string](Get-PropertyValue $entryVal 'alt' '')
            caption = [string](Get-PropertyValue $entryVal 'caption' '')
            size_bytes = $file.Length
            uploaded = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
    return @($items | Sort-Object uploaded -Descending)
}

function Save-MediaUpload {
    param($Payload)
    $name = [string](Get-PropertyValue $Payload 'name' '')
    $folder = [string](Get-PropertyValue $Payload 'folder' 'general')
    $dataUrl = [string](Get-PropertyValue $Payload 'data_url' '')
    $alt = [string](Get-PropertyValue $Payload 'alt' '')
    $caption = [string](Get-PropertyValue $Payload 'caption' '')
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($dataUrl)) { throw 'Missing file name or image data.' }
    if ($folder -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid media folder.' }
    $ext = [IO.Path]::GetExtension($name).ToLowerInvariant()
    if ($mediaImageExtensions -notcontains $ext) { throw 'Unsupported image type.' }
    $parts = $dataUrl -split ',',2
    if ($parts.Count -ne 2) { throw 'Invalid image data.' }
    $bytes = [Convert]::FromBase64String($parts[1])
    if ($bytes.Length -gt 12MB) { throw 'Image exceeds 12 MB.' }
    $safeBase = ([IO.Path]::GetFileNameWithoutExtension($name).ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeBase)) { $safeBase='image' }
    $fileName = "$safeBase$ext"
    $imagesRoot = Join-Path $root 'images'
    $target = Join-Path $imagesRoot $fileName
    $n=2
    while (Test-Path $target) { $fileName="$safeBase-$n$ext"; $target=Join-Path $imagesRoot $fileName; $n++ }
    [IO.File]::WriteAllBytes($target,$bytes)

    $meta = Get-MediaMeta
    $meta | Add-Member -MemberType NoteProperty -Name $fileName -Value ([pscustomobject]@{ folder=$folder; alt=$alt; caption=$caption }) -Force
    Save-MediaMeta $meta

    return [pscustomobject]@{ id=$fileName; file="images/$fileName"; name=$fileName; folder=$folder; alt=$alt; caption=$caption; size_bytes=$bytes.Length }
}

function Update-MediaMetadata {
    param($Payload)
    $id = [string](Get-PropertyValue $Payload 'id' '')
    if ([string]::IsNullOrWhiteSpace($id)) { return @{success=$false; error='Falta el id de la imagen.'} }
    $meta = Get-MediaMeta
    $existing = $meta.PSObject.Properties[$id]
    $existingVal = if ($existing) { $existing.Value } else { $null }
    $updated = [pscustomobject]@{
        folder = [string](Get-PropertyValue $Payload 'folder' (Get-PropertyValue $existingVal 'folder' 'general'))
        alt = [string](Get-PropertyValue $Payload 'alt' (Get-PropertyValue $existingVal 'alt' ''))
        caption = [string](Get-PropertyValue $Payload 'caption' (Get-PropertyValue $existingVal 'caption' ''))
    }
    $meta | Add-Member -MemberType NoteProperty -Name $id -Value $updated -Force
    Save-MediaMeta $meta
    return @{success=$true}
}

function Get-ContentType {
    param([string]$Path)
    switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { return 'text/html; charset=utf-8' }
        '.css' { return 'text/css; charset=utf-8' }
        '.js' { return 'application/javascript; charset=utf-8' }
        '.json' { return 'application/json; charset=utf-8' }
        '.svg' { return 'image/svg+xml' }
        '.png' { return 'image/png' }
        '.jpg' { return 'image/jpeg' }
        '.jpeg' { return 'image/jpeg' }
        '.webp' { return 'image/webp' }
        default { return 'application/octet-stream' }
    }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($baseUrl)
$listener.Start()

Write-Host "Wild CMS v1.1 running at $baseUrl" -ForegroundColor Cyan
Write-Host 'Press Ctrl+C to stop.' -ForegroundColor DarkGray
if (-not $NoOpen) { Start-Process $baseUrl }

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $path = $request.Url.AbsolutePath
        try {

            if ($path -eq '/api/media' -and $request.HttpMethod -eq 'GET') {
                Send-Json $context @{ items=@(Get-MediaIndex) }
                continue
            }
            if ($path -eq '/api/media/upload' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Save-MediaUpload $payload)
                continue
            }
            if ($path -eq '/api/media/update' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Update-MediaMetadata $payload)
                continue
            }
            if ($path.StartsWith('/project-media/') -and $request.HttpMethod -eq 'GET') {
                $relativeMedia = $path.Substring('/project-media/'.Length) -replace '/','\\'
                $mediaBase = [IO.Path]::GetFullPath((Join-Path $root 'images'))
                $mediaFile = [IO.Path]::GetFullPath((Join-Path $mediaBase $relativeMedia))
                if (-not $mediaFile.StartsWith($mediaBase,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $mediaFile -PathType Leaf)) {
                    Send-Text $context 'Not Found' 'text/plain' 404
                    continue
                }
                $bytes=[IO.File]::ReadAllBytes($mediaFile)
                $context.Response.StatusCode=200
                $context.Response.ContentType=Get-ContentType $mediaFile
                $context.Response.ContentLength64=$bytes.Length
                $context.Response.OutputStream.Write($bytes,0,$bytes.Length)
                $context.Response.OutputStream.Close()
                continue
            }

            if ($path -eq '/api/state' -and $request.HttpMethod -eq 'GET') {
                Send-Json $context (Get-ControlState)
                continue
            }
            if ($path -eq '/api/content/validate' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Validate-Article $payload)
                continue
            }
            if ($path -eq '/api/content/save' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Save-ArticleDraft $payload)
                continue
            }
            if ($path -eq '/api/content/publish' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                $article = Get-PropertyValue $payload 'article' $payload
                $runGenerator = [bool](Get-PropertyValue $payload 'run_generator' $true)
                Send-Json $context (Publish-Article $article $runGenerator)
                continue
            }
            if ($path -eq '/api/content/draft' -and $request.HttpMethod -eq 'GET') {
                $slug = $request.QueryString['slug']
                $draftPath = Join-Path $root "knowledge\content\drafts\$slug.json"
                if (-not (Test-Path $draftPath)) { Send-Json $context @{error='Borrador no encontrado'} 404; continue }
                Send-Json $context (Read-JsonSafe $draftPath $null)
                continue
            }
            if ($path -eq '/api/content/published' -and $request.HttpMethod -eq 'GET') {
                $slug = $request.QueryString['slug']
                $blogPath = Join-Path $root 'blog-data.json'
                $articles = if (Test-Path $blogPath) { @(Read-JsonSafe $blogPath @()) } else { @() }
                $match = $articles | Where-Object { [string]$_.slug -eq $slug } | Select-Object -First 1
                if (-not $match) { Send-Json $context @{error='Artículo no encontrado'} 404; continue }
                Send-Json $context $match
                continue
            }
            if ($path -eq '/api/content/suggest-links' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context @{ suggestions = Get-LinkSuggestions $payload }
                continue
            }
            if ($path -eq '/api/content/auto-draft' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (New-ArticleAutoDraft $payload)
                continue
            }
            if ($path -eq '/api/run' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                $name = [string](Get-PropertyValue $payload 'name' '')
                Send-Json $context (Run-AllowedCommand $name)
                continue
            }
            if ($path -eq '/api/hotel/create' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (New-Hotel $payload)
                continue
            }
            if ($path -eq '/api/destination/import-url' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (New-DestinationFromUrl $payload)
                continue
            }
            if ($path -eq '/api/hotel/import-url' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (New-HotelFromUrl $payload)
                continue
            }
            if ($path -eq '/api/hotel/complete' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                $id = [string](Get-PropertyValue $payload 'id' '')
                if ([string]::IsNullOrWhiteSpace($id)) { Send-Json $context @{ success=$false; error='Falta el id del hotel.' } 400; continue }
                Send-Json $context (Complete-HotelIntelligence $id)
                continue
            }
            if ($path -eq '/api/hotel/quality' -and $request.HttpMethod -eq 'GET') {
                $id = $request.QueryString['id']
                Send-Json $context (Get-HotelQualityReport $id)
                continue
            }
            if ($path -eq '/api/hotel/publish' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Publish-Hotel $payload)
                continue
            }
            if ($path -eq '/api/hotel/detail' -and $request.HttpMethod -eq 'GET') {
                $id = $request.QueryString['id']
                $detail = Get-HotelDetail $id
                if (-not $detail) { Send-Json $context @{ error='Hotel no encontrado.' } 404; continue }
                Send-Json $context $detail
                continue
            }
            if ($path -eq '/api/hotel/update' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Update-HotelFields $payload)
                continue
            }
            if ($path -eq '/api/tour/detail' -and $request.HttpMethod -eq 'GET') {
                $id = $request.QueryString['id']
                $detail = Get-TourDetail $id
                if (-not $detail) { Send-Json $context @{ error='Tour no encontrado.' } 404; continue }
                Send-Json $context $detail
                continue
            }
            if ($path -eq '/api/tour/update' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Update-TourFields $payload)
                continue
            }
            if ($path -eq '/api/categories/list' -and $request.HttpMethod -eq 'GET') {
                Send-Json $context @{ success=$true; categories=(Get-Categories) }
                continue
            }
            if ($path -eq '/api/categories/save' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Save-Category $payload)
                continue
            }
            if ($path -eq '/api/categories/delete' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Remove-Category $payload)
                continue
            }
            if ($path -eq '/api/destination/detail' -and $request.HttpMethod -eq 'GET') {
                $id = $request.QueryString['id']
                $detail = Get-DestinationDetail $id
                if (-not $detail) { Send-Json $context @{ error='Destino no encontrado.' } 404; continue }
                Send-Json $context $detail
                continue
            }
            if ($path -eq '/api/destination/update' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Update-DestinationFields $payload)
                continue
            }

            if ($path -eq '/api/reports/destination-health' -and $request.HttpMethod -eq 'GET') {
                $healthPath = Join-Path $root 'reports\destination-health.json'
                Send-Json $context @{ success=$true; destinations=(Read-JsonSafe $healthPath @()) }
                continue
            }
            if ($path -eq '/api/question/list' -and $request.HttpMethod -eq 'GET') {
                Send-Json $context @{ success=$true; questions=(Get-Questions) }
                continue
            }
            if ($path -eq '/api/question/analyze' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (New-QuestionAnalysis $payload)
                continue
            }
            if ($path -eq '/api/question/save' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Save-Question $payload)
                continue
            }
            if ($path -eq '/api/question/update' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Update-Question $payload)
                continue
            }
            if ($path -eq '/api/question/publish' -and $request.HttpMethod -eq 'POST') {
                $payload = Read-RequestJson $request
                Send-Json $context (Publish-Question $payload)
                continue
            }

            if ($request.HttpMethod -eq 'OPTIONS' -and $path -eq '/api/analytics/event') {
                $context.Response.Headers.Add('Access-Control-Allow-Origin', '*')
                $context.Response.Headers.Add('Access-Control-Allow-Methods', 'POST, OPTIONS')
                $context.Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
                $context.Response.StatusCode = 204
                $context.Response.OutputStream.Close()
                continue
            }
            if ($path -eq '/api/analytics/event' -and $request.HttpMethod -eq 'POST') {
                $context.Response.Headers.Add('Access-Control-Allow-Origin', '*')
                $payload = Read-RequestJson $request
                Send-Json $context (Write-AnalyticsEvent $payload)
                continue
            }
            if ($path -eq '/api/analytics/summary' -and $request.HttpMethod -eq 'GET') {
                Send-Json $context (Get-AnalyticsSummary)
                continue
            }
            if ($path.StartsWith('/blog/') -and $request.HttpMethod -eq 'GET') {
                $blogRoot = [IO.Path]::GetFullPath((Join-Path $root 'blog'))
                $relBlog = ($path.Substring('/blog/'.Length)) -replace '/', '\'
                $blogFile = [IO.Path]::GetFullPath((Join-Path $blogRoot $relBlog))
                if ($blogFile.StartsWith($blogRoot,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path $blogFile -PathType Leaf)) {
                    $bytes = [IO.File]::ReadAllBytes($blogFile)
                    $context.Response.StatusCode = 200
                    $context.Response.ContentType = Get-ContentType $blogFile
                    $context.Response.ContentLength64 = $bytes.Length
                    $context.Response.OutputStream.Write($bytes,0,$bytes.Length)
                    $context.Response.OutputStream.Close()
                } else { Send-Text $context 'Not Found' 'text/plain' 404 }
                continue
            }

            $relative = $path.TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($relative)) { $relative = 'index.html' }
            $filePath = Join-Path $webRoot ($relative -replace '/', '\')
            $resolvedRoot = [IO.Path]::GetFullPath($webRoot)
            $resolvedFile = [IO.Path]::GetFullPath($filePath)
            if (-not $resolvedFile.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
                Send-Text $context 'Forbidden' 'text/plain' 403
                continue
            }
            if (-not (Test-Path $resolvedFile -PathType Leaf)) {
                # Not part of the admin UI bundle -- fall back to the generated
                # public site (hotels/, destinations/, tours/, images/, etc.)
                # so links from generated pages resolve on this same server.
                $siteFilePath = Join-Path $root ($relative -replace '/', '\')
                $siteRoot = [IO.Path]::GetFullPath($root)
                $siteResolvedFile = [IO.Path]::GetFullPath($siteFilePath)
                if ($siteResolvedFile.StartsWith($siteRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $siteResolvedFile -PathType Leaf)) {
                    $resolvedFile = $siteResolvedFile
                } else {
                    Send-Text $context 'Not Found' 'text/plain' 404
                    continue
                }
            }
            $bytes = [IO.File]::ReadAllBytes($resolvedFile)
            $context.Response.StatusCode = 200
            $context.Response.ContentType = Get-ContentType $resolvedFile
            # The CMS's own UI files (index.html/app.js/styles.css) change constantly during a work
            # session -- without this, browsers can keep serving a stale cached copy after a restart,
            # silently hiding fixes just applied (this is what happened with the travel_tip field).
            if ($resolvedFile.StartsWith($webRoot, [StringComparison]::OrdinalIgnoreCase)) {
                $context.Response.Headers.Add('Cache-Control', 'no-cache, no-store, must-revalidate')
            }
            $context.Response.ContentLength64 = $bytes.Length
            $context.Response.OutputStream.Write($bytes,0,$bytes.Length)
            $context.Response.OutputStream.Close()
        }
        catch {
            try { Send-Json $context @{ error=$_.Exception.Message } 500 } catch {}
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
