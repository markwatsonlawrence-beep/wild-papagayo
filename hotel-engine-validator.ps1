# Wild Papagayo - Hotel Engine Output Validator v1.0
[CmdletBinding()]param()
$ErrorActionPreference="Stop";$root=$PSScriptRoot;$errors=@();$warnings=@()
$hotelDir=Join-Path $root "knowledge\hotels";$outDir=Join-Path $root "hotels"
if(-not(Test-Path $hotelDir)){$errors+="Missing knowledge/hotels directory"}
if(-not(Test-Path $outDir)){$errors+="Missing generated hotels directory"}
if($errors.Count -eq 0){foreach($f in @(Get-ChildItem $hotelDir -Filter "*.json" -File)){try{$h=[IO.File]::ReadAllText($f.FullName)|ConvertFrom-Json;if(([string]$h.status) -eq "disabled"){continue};$p=Join-Path $outDir "$($h.slug).html";if(-not(Test-Path $p)){$errors+="$($f.Name): generated page missing"}else{$text=[IO.File]::ReadAllText($p);foreach($marker in @('__HOTEL_','__TOUR_','__FAQ_','__SCHEMA__')){if($text.Contains($marker)){$errors+="$($f.Name): unresolved template marker $marker"}}}}catch{$errors+="$($f.Name): $($_.Exception.Message)"}}}
$report=@("Wild Engine - Hotel Engine Validation","Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))","Errors: $($errors.Count)","Warnings: $($warnings.Count)")
if($errors.Count){$report+="";$report+="ERRORS";$report+=@($errors|ForEach-Object{"- $_"})}
[IO.File]::WriteAllLines((Join-Path $root "hotel-engine-report.txt"),[string[]]$report,[Text.UTF8Encoding]::new($false))
if($errors.Count){Write-Host "Hotel Engine validation failed." -ForegroundColor Red;exit 1}else{Write-Host "Hotel Engine validation passed." -ForegroundColor Green;Write-Host "Hotels: $(@(Get-ChildItem $hotelDir -Filter '*.json' -File).Count) | Warnings: 0";exit 0}
