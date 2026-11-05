[CmdletBinding()]
param([ValidateSet('hotel')][string]$EntityType='hotel',[Parameter(Mandatory=$true)][string]$EntityId)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$sourcePath=Join-Path $root "knowledge/sources/$($EntityType)s/$EntityId.json"
$draftPath=Join-Path $root "knowledge/imports/$($EntityType)s/$EntityId-draft.json"
$errors=@(); $warnings=@()
if(-not(Test-Path $sourcePath)){$errors+="Missing source configuration: $sourcePath"}
if(-not(Test-Path $draftPath)){$errors+="Missing generated draft: $draftPath"}
if($errors.Count -eq 0){
 $source=[IO.File]::ReadAllText($sourcePath)|ConvertFrom-Json
 $draft=[IO.File]::ReadAllText($draftPath)|ConvertFrom-Json
 if($draft.entity_id -ne $source.entity_id){$errors+='Draft entity_id does not match source configuration.'}
 if(@($draft.source_results).Count -eq 0){$errors+='No official source was processed successfully.'}
 if(@($draft.gallery_candidates).Count -eq 0){$warnings+='No gallery candidates were detected.'}
 foreach($img in @($draft.gallery_candidates)){if($img.usage_status -ne 'permission_required'){$errors+='An image candidate is missing permission_required status.';break}}
 if($draft.publishing_allowed -ne $false){$errors+='Research drafts must not be marked publishing_allowed.'}
}
if($errors.Count){Write-Host 'Wild Data validation failed.' -ForegroundColor Red;$errors|%{Write-Host "- $_" -ForegroundColor Red};exit 1}
Write-Host 'Wild Data validation passed.' -ForegroundColor Green
Write-Host "Warnings: $($warnings.Count)"
$warnings|%{Write-Host "- $_" -ForegroundColor Yellow}
