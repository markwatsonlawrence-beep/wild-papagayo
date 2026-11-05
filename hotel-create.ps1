# ============================================================
# Wild Papagayo - Hotel Create v1.0
# Scaffolds a new knowledge/master/hotels/<slug>.json record from
# just a hotel name, so the existing intelligence pipeline
# (experience-builder, wild-intelligence-engine, certification,
# relationship-engine, recommendation-engine, hotel-generator)
# can complete it. Usage: .\hotel-create.ps1 -HotelName "..."
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$HotelName
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$masterDir = Join-Path $root 'knowledge\master\hotels'
New-Item -ItemType Directory -Force -Path $masterDir | Out-Null

$slug = $HotelName.ToLowerInvariant() -replace '[^a-z0-9]+','-'
$slug = $slug.Trim('-')
if ([string]::IsNullOrWhiteSpace($slug)) { throw 'Hotel name must contain at least one letter or number.' }

$targetPath = Join-Path $masterDir "$slug.json"
if (Test-Path $targetPath) { throw "A hotel with id '$slug' already exists." }

# Normalize casing (protects against inputs like "hOTEL bOSQUE DEL MAR" from
# stray caps lock) while keeping small Spanish connector words lowercase.
$textInfo = (Get-Culture).TextInfo
$lowercaseWords = @('de','del','la','las','los','y','en','el')
$titleCased = $textInfo.ToTitleCase($HotelName.ToLowerInvariant())
$wordParts = $titleCased -split ' ' | ForEach-Object { if ($lowercaseWords -contains $_.ToLowerInvariant()) { $_.ToLowerInvariant() } else { $_ } }
$HotelName = ($wordParts -join ' ')

$description = "$HotelName is a newly added property in the Wild Papagayo Experience Guide. This description is a placeholder and should be reviewed and completed with real official details before publication."

$hotel = [ordered]@{
    identity = [ordered]@{
        id = $slug
        official_name = $HotelName
        display_name = $HotelName
        slug = $slug
        brand = ''
        category = ''
        luxury_level = ''
    }
    location = [ordered]@{
        destination_id = 'papagayo'
        location_label = 'Peninsula Papagayo'
        province = 'Guanacaste'
        airport_id = 'lir'
        tour_pickup_zone = 'papagayo'
        transfer = [ordered]@{
            min = 35
            max = 50
            label = 'Approximately 35-50 minutes from Guanacaste Airport (LIR), depending on traffic.'
            source_type = 'wild_papagayo_operational_estimate'
        }
    }
    official_sources = @(
        [ordered]@{ source_id = 'pending'; type = 'official'; url = '' }
    )
    official_facts = [ordered]@{ summary = '' }
    editorial = [ordered]@{
        hero_description = ''
        description = $description
        tone = 'useful, locally informed and guest-focused'
    }
    traveler_profiles = @('Travelers')
    experience_scores = [ordered]@{
        luxury = [ordered]@{ score = 3; reason = '' }
        families = [ordered]@{ score = 3; reason = '' }
        couples = [ordered]@{ score = 3; reason = '' }
        wellness = [ordered]@{ score = 3; reason = '' }
        adventure_access = [ordered]@{ score = 3; reason = '' }
        walkability = [ordered]@{ score = 3; reason = '' }
        nightlife = [ordered]@{ score = 3; reason = '' }
    }
    wild_insights = [ordered]@{
        local_take = "$HotelName is a recent addition to the Wild Papagayo guide. Local insight is pending editorial review."
        insights = @()
    }
    recommendations = [ordered]@{
        featured_tours = @()
        related_articles = @()
        nearby_destinations = @('papagayo')
    }
    faq = @()
    amenities = @()
    room_types = @()
    traveler_profile_reasons = @()
    gallery = [ordered]@{
        hero_image = 'images/luxury-costa-rica-tours-hero.webp'
        hero_image_alt = "$HotelName"
        hero_image_status = 'temporary_placeholder'
        approved_images = @()
        candidate_images = @()
        usage_note = 'Only publish owned, licensed or explicitly authorized hotel imagery.'
    }
    seo = [ordered]@{
        title = "$HotelName Guide | Tours, Transfers & Local Tips"
        description = "Plan your stay at $HotelName with recommended tours, private airport transfers and local Guanacaste insight."
        keywords = @("$HotelName tours", "$HotelName transfer", "things to do near $HotelName")
    }
    verification = [ordered]@{
        status = 'unverified'
        last_verified = ''
        official_source = ''
        note = 'Official hotel details have not been verified yet.'
    }
    workflow = [ordered]@{
        status = 'draft'
        editorial_standard = 'Wild Papagayo Hotel Gold Standard v2.0'
        publication_threshold = 90
    }
}

$json = $hotel | ConvertTo-Json -Depth 15
[System.IO.File]::WriteAllText($targetPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host 'Hotel record created.' -ForegroundColor Green
Write-Host "  id:   $slug"
Write-Host "  path: $targetPath"
Write-Host ''

[pscustomobject]@{ id = $slug; path = $targetPath } | ConvertTo-Json -Compress
