Set-StrictMode -Version 2.0

function Get-WildPropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($property -and $null -ne $property.Value) { return $property.Value }
    return $Default
}

function Test-WildText {
    param($Value)
    return (-not [string]::IsNullOrWhiteSpace([string]$Value))
}

function Get-WildCollectionCount {
    param($Value)
    if ($null -eq $Value) { return 0 }
    return @($Value).Count
}


function Get-WildSectionScore {
    param(
        [string]$Name,
        [double]$Percent,
        [double]$Weight,
        [string[]]$Notes
    )
    $bounded = [Math]::Max(0, [Math]::Min(100, $Percent))
    [pscustomobject]@{
        name = $Name
        percent = [Math]::Round($bounded, 1)
        weight = $Weight
        weighted_points = [Math]::Round(($bounded / 100.0) * $Weight, 2)
        notes = @($Notes)
    }
}

function Measure-WildHotelCertification {
    param($Master, $Rules)

    $identity      = Get-WildPropertyValue $Master 'identity'
    $editorial     = Get-WildPropertyValue $Master 'editorial'
    $insights      = Get-WildPropertyValue $Master 'wild_insights'
    $location      = Get-WildPropertyValue $Master 'location'
    $recommendations = Get-WildPropertyValue $Master 'recommendations'
    $verification  = Get-WildPropertyValue $Master 'verification'
    $workflow      = Get-WildPropertyValue $Master 'workflow'
    $official      = Get-WildPropertyValue $Master 'official_facts'

    $workflowStatus = [string](Get-WildPropertyValue $workflow 'status' '')
    $factStatus     = [string](Get-WildPropertyValue $official 'fact_status' '')

    # --- 6-dimension certification ---
    $Certification = [PSCustomObject]@{
        Knowledge       = 0
        Experience      = 0
        Transportation  = 0
        Recommendations = 0
        Editorial       = 0
        Verification    = 0
    }

    if (Test-WildText (Get-WildPropertyValue $editorial 'description')) {
        $Certification.Knowledge = 100
    }

    if (Test-WildText (Get-WildPropertyValue $insights 'local_take')) {
        $Certification.Experience = 100
    }

    if ($null -ne (Get-WildPropertyValue $location 'transfer')) {
        $Certification.Transportation = 100
    }

    if ((Get-WildCollectionCount (Get-WildPropertyValue $recommendations 'featured_tours' @())) -gt 0) {
        $Certification.Recommendations = 100
    }

    if ((Get-WildCollectionCount (Get-WildPropertyValue $Master 'faq' @())) -ge 3) {
        $Certification.Editorial = 100
    }

    $verificationStatus = [string](Get-WildPropertyValue $verification 'status' '')
    if ($verificationStatus -eq 'reviewed' -or $verificationStatus -eq 'verified') {
        $Certification.Verification = 100
    }

    # --- Overall score ---
    $OverallScore = [Math]::Round((
        $Certification.Knowledge +
        $Certification.Experience +
        $Certification.Transportation +
        $Certification.Recommendations +
        $Certification.Editorial +
        $Certification.Verification
    ) / 6.0, 1)

    # --- Build sections array ---
    $sections = @()
    foreach ($key in @('Knowledge','Experience','Transportation','Recommendations','Editorial','Verification')) {
        $val = [double]($Certification.PSObject.Properties[$key].Value)
        $sections += Get-WildSectionScore $key $val (100.0 / 6.0) @()
    }

    # --- Certification level ---
    $certLevel = 'Not Certified'
    $certificationReason = 'No certification level requirements were met.'
    foreach ($level in @($Rules.certification_levels | Sort-Object { [double]$_.min_score } -Descending)) {
        $meetsScore    = $OverallScore -ge [double]$level.min_score
        $meetsWorkflow = (-not [bool]$level.requires_approved_workflow) -or ($workflowStatus -eq 'approved' -or $workflowStatus -eq 'published')
        $meetsFacts    = (-not [bool]$level.requires_verified_facts) -or ($factStatus -eq 'verified')
        if ($meetsScore -and $meetsWorkflow -and $meetsFacts) {
            $certLevel = [string]$level.name
            $certificationReason = "Meets $certLevel certification requirements."
            break
        }
    }

    # --- Blocking issues ---
    $blockingIssues = @()
    if ($Certification.Knowledge -eq 0)       { $blockingIssues += 'Local knowledge description is missing.' }
    if ($Certification.Experience -eq 0)      { $blockingIssues += 'Local Insight is missing.' }
    if ($Certification.Transportation -eq 0)  { $blockingIssues += 'Transportation information is missing.' }
    if ($Certification.Recommendations -eq 0) { $blockingIssues += 'Recommendation is missing — add at least 1 featured tour.' }
    if ($Certification.Editorial -eq 0)       { $blockingIssues += 'Suggested Stay missing — add at least 3 FAQ entries.' }
    if ($Certification.Verification -eq 0)    { $blockingIssues += 'Editorial review pending — set verification.status to reviewed.' }
    if ($factStatus -ne 'verified')           { $blockingIssues += 'Complete official fact verification.' }
    if ($workflowStatus -ne 'approved' -and $workflowStatus -ne 'published') {
        $blockingIssues += "Change editorial workflow status to approved after final review."
    }

    [pscustomobject]@{
        entity_id            = [string](Get-WildPropertyValue $identity 'id' '')
        entity_name          = [string](Get-WildPropertyValue $identity 'official_name' '')
        generated_at         = (Get-Date).ToString('s')
        overall_score        = $OverallScore
        certification        = $certLevel
        certification_reason = $certificationReason
        publication_ready    = ($OverallScore -ge [double]$Rules.publication_threshold -and $blockingIssues.Count -eq 0)
        workflow_status      = $workflowStatus
        fact_status          = $factStatus
        sections             = @($sections)
        blocking_issues      = @($blockingIssues)
    }
}

function ConvertTo-WildCertificationHtml {
    param($Result)
    $rows = ''
    foreach ($section in @($Result.sections)) {
        $notes = if (@($section.notes).Count -gt 0) { '<small>' + ((@($section.notes) -join ' · ') -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;') + '</small>' } else { '' }
        $rows += "<tr><td><strong>$($section.name)</strong>$notes</td><td>$($section.percent)%</td><td><div class='bar'><span style='width:$($section.percent)%'></span></div></td></tr>"
    }
    $issues = if (@($Result.blocking_issues).Count -gt 0) { '<ul>' + ((@($Result.blocking_issues) | ForEach-Object { '<li>' + ($_ -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;') + '</li>' }) -join '') + '</ul>' } else { '<p>No blocking issues.</p>' }
    @"
<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>$($Result.entity_name) Certification</title><style>body{font-family:Arial,sans-serif;background:#f6f7f9;color:#09284a;margin:0;padding:32px}.wrap{max-width:960px;margin:auto}.hero{background:#08294d;color:white;padding:32px;border-radius:14px}.score{font-size:52px;font-weight:800}.cert{display:inline-block;background:#d1a23e;color:#08294d;padding:8px 14px;border-radius:999px;font-weight:800}.card{background:#fff;border:1px solid #e3e7ec;border-radius:14px;padding:24px;margin-top:20px}table{width:100%;border-collapse:collapse}td{padding:14px;border-bottom:1px solid #edf0f4}small{display:block;color:#7b8794;margin-top:5px}.bar{height:9px;background:#e9edf2;border-radius:99px;overflow:hidden}.bar span{display:block;height:100%;background:#d1a23e}.ready{font-weight:800;color:#16805c}.notready{font-weight:800;color:#b23a3a}</style></head><body><div class='wrap'><div class='hero'><div class='cert'>$($Result.certification)</div><h1>$($Result.entity_name)</h1><div class='score'>$($Result.overall_score)%</div><p class='$(if($Result.publication_ready){'ready'}else{'notready'})'>$(if($Result.publication_ready){'Ready for publication'}else{'Review required'})</p></div><div class='card'><h2>Certification sections</h2><table>$rows</table></div><div class='card'><h2>Blocking issues</h2>$issues</div></div></body></html>
"@
}
