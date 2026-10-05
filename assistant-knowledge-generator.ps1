# ============================================================
# Wild Papagayo - AI Assistant Knowledge Compiler v1.0
# Compiles a single compact JSON snapshot of the whole knowledge
# graph (hotels, tours, destinations, articles, months, FAQ) for
# the AI Travel Assistant's grounding context. Small enough (this
# site's current scale: ~9 hotels, 32 tours, 8 destinations, 22
# articles) to pass in full as system-prompt context rather than
# building a real retrieval index -- keeps the assistant honest
# by construction: it can only ever answer from what's here.
# Run this after any content change, then redeploy.
# ============================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
# Written to BOTH function directories from this same execution so they stay
# byte-identical. functions/assistant.js (Cloudflare Pages Functions) is the
# path actually served in production; netlify/functions/assistant.js is kept
# in place (not proven dead code, not removed here) but was previously never
# updated by this generator at all -- that mismatch is fixed by writing both
# from one run instead of picking one over the other.
$outPathCloudflare = Join-Path $root "functions\assistant-knowledge.json"
$outPathNetlify = Join-Path $root "netlify\functions\assistant-knowledge.json"
New-Item -ItemType Directory -Force (Split-Path $outPathCloudflare -Parent) | Out-Null
New-Item -ItemType Directory -Force (Split-Path $outPathNetlify -Parent) | Out-Null

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }

$hotels = Get-ChildItem (Join-Path $root 'knowledge\master\hotels') -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' } | ForEach-Object {
    $h = Read-Utf8Json $_.FullName
    # Strict eligibility gate: only a record whose workflow.status is exactly
    # "published" may reach Bubu. Every other value -- missing, "draft", or
    # anything else -- is excluded. This is deliberately narrower than a
    # "not disabled" check: workflow.status is currently "published" on every
    # record in this directory regardless of whether the hotel's page has
    # ever actually been deployed, so treating anything but an explicit
    # "published" as ineligible is the only gate that can't silently let an
    # unfinished or undeployed hotel through.
    if ([string]$h.workflow.status -ne 'published') { return }
    [ordered]@{
        name = if ($h.identity.display_name) { [string]$h.identity.display_name } else { [string]$h.identity.official_name }
        category = [string]$h.identity.category
        location = [string]$h.location.location_label
        description = [string]$h.editorial.description
        url = "/hotels/$($_.BaseName)"
    }
}

$tours = Get-ChildItem (Join-Path $root 'knowledge\tours') -Filter '*.json' -File | ForEach-Object {
    $t = Read-Utf8Json $_.FullName
    [ordered]@{
        name = [string]$t.name
        category = [string]$t.category
        difficulty = [string]$t.difficulty
        duration = [string]$t.duration_label
        best_for = @($t.best_for)
        description = [string]$t.short_description
        url = [string]($t.page_url -replace '^\.\./', '/')
    }
}

$destinations = Get-ChildItem (Join-Path $root 'knowledge\destinations') -Filter '*.json' -File | ForEach-Object {
    $d = Read-Utf8Json $_.FullName
    # Strict eligibility gate: only status "published" may reach Bubu. Missing,
    # "draft", "disabled" or unknown values are excluded, so a newly created
    # destination cannot be described (or linked) before its page is live.
    if ([string]$d.status -ne 'published') { return }
    [ordered]@{
        name = [string]$d.name
        province = [string]$d.province
        best_season = [string]$d.best_season
        description = [string]$d.description
        url = "/destinations/$($_.BaseName)"
    }
}

# Transfers -- sourced from the same knowledge/landing-pages/*.json configs
# landing-page-generator.ps1 uses, filtered to output_dir === 'transfers'
# only (that folder also holds private-tours hub/hotel landing pages, which
# are intentionally excluded here -- they are not transfer services and
# would duplicate/confuse the tours category). Only fields that already
# exist in the source config are used -- no price, availability, policy,
# or condition field is invented; travel_time is derived directly from the
# source's own numeric min/max fields, not a new claim.
$transferConfigs = Get-ChildItem (Join-Path $root 'knowledge\landing-pages') -Filter '*.json' -File | ForEach-Object {
    Read-Utf8Json $_.FullName
} | Where-Object { [string]$_.output_dir -eq 'transfers' }

$transfers = $transferConfigs | ForEach-Object {
    $lp = $_
    $firstRow = @($lp.travel_times.rows) | Select-Object -First 1
    [ordered]@{
        name = [string]$lp.h1
        origin = [string]$lp.travel_times.origin_label
        destination = if ($firstRow) { [string]$firstRow.destination } else { '' }
        travel_time = if ($firstRow -and $firstRow.min -and $firstRow.max) { "$($firstRow.min)-$($firstRow.max) minutes" } else { '' }
        description = [string]$lp.seo_description
        url = "/$($lp.output_dir)/$($lp.slug)"
    }
}

$blogPath = Join-Path $root 'blog-data.json'
$articles = if (Test-Path $blogPath) { @(Read-Utf8Json $blogPath) } else { @() }
# Same status gate as blog-generator.ps1: an article isn't necessarily live
# just because it has a record in blog-data.json, so Bubu must not learn
# about (and link to) a page that doesn't actually exist on the site.
$articleSummaries = $articles | Where-Object { -not $_.status -or [string]$_.status -eq 'published' } | ForEach-Object {
    [ordered]@{
        title = [string]$_.title
        category = [string]$_.category
        excerpt = [string]$_.excerpt
        url = "/blog/$($_.slug)"
    }
}

$knowledge = [ordered]@{
    generated = (Get-Date).ToString('yyyy-MM-dd')
    company = [ordered]@{
        name = 'Wild Papagayo'
        description = 'A private tour and transportation company operating in Guanacaste and Arenal, Costa Rica. Offers private day tours, airport transfers and private drivers -- not group bus tours.'
        whatsapp = 'https://wa.me/50688566325'
        service_area = 'Guanacaste (Papagayo, Playa Coco, Playa Hermosa, Tamarindo, Flamingo, Rincon de la Vieja) and Arenal/La Fortuna'
        # Mirrors the standard policy on /politicasdecancelacion (keep both in sync).
        booking_policy = [ordered]@{
            deposit = 'A 25% deposit confirms a booking.'
            final_balance = 'The remaining 75% is due no later than 72 hours before the service begins.'
            bookings_within_72_hours = 'Bookings made within 72 hours of the service require full payment at the time of booking.'
            cancellation_more_than_72_hours = 'Guest-requested cancellations made more than 72 hours before the service receive a refund of the refundable amount paid, less any applicable non-recoverable payment-processing costs when legally permitted.'
            cancellation_within_72_hours = 'Cancellations made within 72 hours of the service are non-refundable, subject to any mandatory consumer rights under Costa Rican law.'
            no_show = 'No-shows are 100% non-refundable, subject to any mandatory consumer rights.'
            date_changes = 'Date changes can be requested more than 72 hours before the service, subject to availability. Within 72 hours there is no automatic right to reschedule; any exceptional change is at Wild Papagayo''s discretion.'
            wild_papagayo_cancels = 'If Wild Papagayo cancels and cannot offer an alternative or new date the guest accepts, the guest receives a 100% refund and Wild Papagayo covers the processing fee and refund cost.'
            weather = 'Normal rain does not automatically qualify for a refund. If an activity cannot operate safely, Wild Papagayo first tries to reschedule, adjust the itinerary or offer a suitable alternative.'
            payment_method = 'The standard electronic payment method is Compra Click (BAC). No card surcharge is added to the published price.'
            refund_costs = 'For international card payments via Compra Click (BAC), the non-recoverable costs are currently the original 2.50% processing fee and a US$8 bank fee per refund. No other fee is deducted.'
            refund_timing = 'Once an approved card refund is submitted, BAC processing currently takes approximately four days; the time for the credit to appear depends on the card issuer.'
            special_services = 'Multi-day journeys, lodging packages and some supplier-operated services may have different written conditions, disclosed before payment.'
            consumer_rights = 'Nothing in this policy limits any mandatory consumer rights under applicable Costa Rican law.'
            url = '/politicasdecancelacion'
        }
    }
    hotels = @($hotels)
    tours = @($tours)
    destinations = @($destinations)
    articles = @($articleSummaries)
    transfers = @($transfers)
}

$json = $knowledge | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($outPathCloudflare, $json, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($outPathNetlify, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Compiled assistant knowledge: $($hotels.Count) hotels, $($tours.Count) tours, $($destinations.Count) destinations, $($articleSummaries.Count) articles, $($transfers.Count) transfers."
Write-Host "-> $outPathCloudflare"
Write-Host "-> $outPathNetlify"
