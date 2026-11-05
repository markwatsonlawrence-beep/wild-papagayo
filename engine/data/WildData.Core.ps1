Set-StrictMode -Version 2.0

function ConvertTo-WildPlainText {
    param([AllowNull()][string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return "" }
    $text = $Html -replace '(?is)<script\b[^>]*>.*?</script>', ' '
    $text = $text -replace '(?is)<style\b[^>]*>.*?</style>', ' '
    $text = $text -replace '(?is)<[^>]+>', ' '
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    return (($text -replace '\s+', ' ').Trim())
}

function Get-WildHtmlAttribute {
    param([string]$Tag, [string]$Name)
    $escaped = [regex]::Escape($Name)
    $match = [regex]::Match($Tag, "(?is)\b$escaped\s*=\s*(['\`"])(.*?)\1")
    if ($match.Success) { return [System.Net.WebUtility]::HtmlDecode($match.Groups[2].Value.Trim()) }
    return ""
}

function Resolve-WildUrl {
    param([string]$BaseUrl, [string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return "" }
    try {
        $base = [Uri]$BaseUrl
        return ([Uri]::new($base, $Candidate)).AbsoluteUri
    } catch { return $Candidate }
}

function Get-WildMetaValue {
    param([string]$Html, [string]$Key)
    $tags = [regex]::Matches($Html, '(?is)<meta\b[^>]*>')
    foreach ($m in $tags) {
        $tag = $m.Value
        $name = Get-WildHtmlAttribute $tag 'name'
        $property = Get-WildHtmlAttribute $tag 'property'
        if (($name -ieq $Key) -or ($property -ieq $Key)) {
            return Get-WildHtmlAttribute $tag 'content'
        }
    }
    return ""
}

function Get-WildTitle {
    param([string]$Html)
    $m = [regex]::Match($Html, '(?is)<title\b[^>]*>(.*?)</title>')
    if ($m.Success) { return ConvertTo-WildPlainText $m.Groups[1].Value }
    return ""
}

function Get-WildCanonical {
    param([string]$Html, [string]$BaseUrl)
    $links = [regex]::Matches($Html, '(?is)<link\b[^>]*>')
    foreach ($m in $links) {
        $tag = $m.Value
        if ((Get-WildHtmlAttribute $tag 'rel') -match '(?i)canonical') {
            return Resolve-WildUrl $BaseUrl (Get-WildHtmlAttribute $tag 'href')
        }
    }
    return $BaseUrl
}

function Get-WildHeadings {
    param([string]$Html)
    $result = @()
    $headingMatches = [regex]::Matches($Html, '(?is)<h([1-3])\b[^>]*>(.*?)</h\1>')
    foreach ($m in $headingMatches) {
        $value = ConvertTo-WildPlainText $m.Groups[2].Value
        if ($value -and $value.Length -le 180) {
            $result += [pscustomobject]@{ level = [int]$m.Groups[1].Value; text = $value }
        }
    }
    return @($result | Select-Object -Unique -Property level,text | Select-Object -First 40)
}

function Get-WildJsonLd {
    param([string]$Html)
    $items = @()
    $jsonLdMatches = [regex]::Matches($Html, "(?is)<script\b[^>]*type\s*=\s*(['\`"]?)application/ld\+json\1[^>]*>(.*?)</script>")
    foreach ($m in $jsonLdMatches) {
        $raw = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value.Trim())
        try {
            $obj = $raw | ConvertFrom-Json
            $items += $obj
        } catch { }
    }
    return @($items)
}

function Get-WildImageCandidates {
    param([string]$Html, [string]$BaseUrl)
    $results = @()
    $seen = @{}
    $og = Get-WildMetaValue $Html 'og:image'
    if ($og) {
        $resolved = Resolve-WildUrl $BaseUrl $og
        $seen[$resolved] = $true
        $results += [pscustomobject]@{ url=$resolved; alt='Open Graph image'; category='hero'; source='og:image'; usage_status='permission_required' }
    }
    $tags = [regex]::Matches($Html, '(?is)<img\b[^>]*>')
    foreach ($m in $tags) {
        $tag = $m.Value
        $src = Get-WildHtmlAttribute $tag 'src'
        if (-not $src) { $src = Get-WildHtmlAttribute $tag 'data-src' }
        if (-not $src) { continue }
        $resolved = Resolve-WildUrl $BaseUrl $src
        if ($seen.ContainsKey($resolved)) { continue }
        $seen[$resolved] = $true
        $alt = Get-WildHtmlAttribute $tag 'alt'
        $signal = ($alt + ' ' + $resolved).ToLowerInvariant()
        $category = 'other'
        if ($signal -match 'room|suite|villa|residence|accommodation') { $category='accommodation' }
        elseif ($signal -match 'pool|swim') { $category='pool' }
        elseif ($signal -match 'beach|ocean|coast|sea') { $category='beach' }
        elseif ($signal -match 'spa|wellness|massage') { $category='spa' }
        elseif ($signal -match 'restaurant|dining|bar|grill|food|chef') { $category='dining' }
        elseif ($signal -match 'golf') { $category='golf' }
        elseif ($signal -match 'family|kids|children') { $category='family' }
        $results += [pscustomobject]@{ url=$resolved; alt=$alt; category=$category; source='img'; usage_status='permission_required' }
        if ($results.Count -ge 80) { break }
    }
    return @($results)
}

function Get-WildKeywordSignals {
    param([string]$Html)
    $text = (ConvertTo-WildPlainText $Html).ToLowerInvariant()
    $dictionary = [ordered]@{
        dining = @('restaurant','dining','bar','grill','culinary','chef')
        spa = @('spa','wellness','massage','treatment')
        family = @('family','kids','children','teen')
        golf = @('golf','arnold palmer')
        beach = @('beach','ocean','pacific')
        pool = @('pool','swimming')
        transfer = @('transfer','airport','meet-and-greet')
        activities = @('adventure','activities','experience','excursion')
    }
    $signals = [ordered]@{}
    foreach ($key in $dictionary.Keys) {
        $found = @()
        foreach ($term in $dictionary[$key]) { if ($text.Contains($term)) { $found += $term } }
        $signals[$key] = @($found | Select-Object -Unique)
    }
    return [pscustomobject]$signals
}

function Invoke-WildSourceFetch {
    param([Parameter(Mandatory=$true)]$Source, [string[]]$AllowedDomains, [string]$CacheDirectory, [switch]$Offline)
    $uri = [Uri]$Source.url
    $hostAllowed = $false
    foreach ($domain in $AllowedDomains) {
        if ($uri.Host -ieq $domain -or $uri.Host.EndsWith('.' + $domain, [StringComparison]::OrdinalIgnoreCase)) { $hostAllowed = $true; break }
    }
    if (-not $hostAllowed) { throw "Source domain is not allowed: $($uri.Host)" }
    if (-not (Test-Path $CacheDirectory)) { New-Item -ItemType Directory -Force $CacheDirectory | Out-Null }
    $cachePath = Join-Path $CacheDirectory ($Source.id + '.html')
    if ($Offline) {
        if (-not (Test-Path $cachePath)) { throw "Offline cache is missing: $cachePath" }
        $html = [IO.File]::ReadAllText($cachePath)
        $status = 200
    } else {
        $headers = @{ 'User-Agent'='Mozilla/5.0 (compatible; WildPapagayoDataEngine/1.0; +https://wildpapagayo.com)' }
        $response = Invoke-WebRequest -Uri $Source.url -UseBasicParsing -Headers $headers -TimeoutSec 45 -MaximumRedirection 8
        $html = [string]$response.Content
        $status = [int]$response.StatusCode
        [IO.File]::WriteAllText($cachePath, $html, [Text.UTF8Encoding]::new($false))
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($html)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    return [pscustomobject]@{ html=$html; status=$status; cache_path=$cachePath; sha256=$hash }
}
