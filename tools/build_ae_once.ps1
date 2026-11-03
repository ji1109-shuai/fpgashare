param([string]$TdRoot='D:/AN_LU',[string]$Tag='ae_once')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$project=Join-Path $repo 'td_project'
$runs=Join-Path $project 'camera_to_dsi_display_Runs'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$synName="syn_${Tag}_$stamp"
$phyName="phy_${Tag}_$stamp"
$syn=Join-Path $runs $synName
$phy=Join-Path $runs $phyName
$record=Join-Path $runs "${Tag}_build_$stamp.json"
# New run directories preserve the previous bit and implementation reports.
New-Item -ItemType Directory $syn,$phy | Out-Null
$entry=Join-Path $project 'camera_to_dsi_display.al'
$al=[IO.File]::ReadAllText($entry)
$source=[regex]::Match($al,'(?s)<Source_Files>.*?</Source_Files>').Value
if(-not $source){throw 'Project source list not found'}
# Run directories are two levels below the project entry. TD uses its own
# XML-like dialect, including raw P&R and :: tags; retain that syntax.
$source=[regex]::Replace($source,'Path="\.\./','Path="../../../')
$template=[IO.File]::ReadAllText((Join-Path $runs 'syn_1/camera_to_dsi_display.prj'))
$prj=[regex]::Replace($template,'(?s)<Source_Files>.*?</Source_Files>',[System.Text.RegularExpressions.MatchEvaluator]{param($m) $source})
$utf8=New-Object Text.UTF8Encoding($false)
foreach($dir in @($syn,$phy)){
 [IO.File]::WriteAllText((Join-Path $dir 'camera_to_dsi_display.prj'),$prj,$utf8)
}
$synSettings=[IO.File]::ReadAllText((Join-Path $runs 'syn_1/settings.cfg'))
$phySettings=[IO.File]::ReadAllText((Join-Path $runs 'phy_1/settings.cfg'))
$phySettings=[regex]::Replace($phySettings,'(?m)^set parent .*$',"set parent ../$synName")
[IO.File]::WriteAllText((Join-Path $syn 'settings.cfg'),$synSettings,$utf8)
[IO.File]::WriteAllText((Join-Path $phy 'settings.cfg'),$phySettings,$utf8)
$sourcePaths=@([regex]::Matches($al,'<File Path="([^"]+)"') | ForEach-Object {
 [IO.Path]::GetFullPath((Join-Path $project $_.Groups[1].Value))
})
$missing=@($sourcePaths | Where-Object {-not (Test-Path -LiteralPath $_)})
if($missing.Count){throw "Missing project files: $missing"}
$assets=@(Get-ChildItem -LiteralPath (Join-Path $repo 'user_source/hdl_source') -Filter '*.hex' -File)
foreach($dir in @($syn,$phy)){foreach($asset in $assets){Copy-Item -LiteralPath $asset.FullName -Destination $dir}}
$sourcePaths=@($sourcePaths)+@($assets | ForEach-Object {$_.FullName})+@($entry)
$inputs=@($sourcePaths | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash)
$info=[ordered]@{project=$entry;started=(Get-Date -Format o);synthesis=$syn;implementation=$phy;inputHashes=$inputs;status='running'}
$info | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $record -Encoding UTF8
Write-Output "BUILD_RECORD=$record"
function Invoke-TdStage([string]$dir){
 Push-Location $dir
 try{
  & "$TdRoot/bin/td_commands_prompt.exe" "$TdRoot/doc/scripts/DefaultFlow.tcl"
  if($LASTEXITCODE -ne 0){throw "TD process failed in $dir : $LASTEXITCODE"}
  $log=Get-ChildItem -LiteralPath $dir -Filter 'td_*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $log){throw "TD log not generated in $dir"}
  $errors=Select-String -LiteralPath $log.FullName -Pattern '\b[A-Z]+-[0-9]+\s+(ERROR|FATAL)\b'
  if($errors){throw ($errors | Out-String)}
 }finally{Pop-Location}
}
try{
 Invoke-TdStage $syn
 if(-not (Test-Path -LiteralPath (Join-Path $syn 'camera_to_dsi_display_gate.db'))){throw 'No new synthesis database'}
 Write-Output 'PROJECT_SYNTHESIS_COMPLETE'
 Invoke-TdStage $phy
 $bit=Join-Path $phy 'camera_to_dsi_display.bit'
 if(-not (Test-Path -LiteralPath $bit)){throw 'No new bit file'}
 $timing=[IO.File]::ReadAllText((Join-Path $phy 'camera_to_dsi_display_phy.ts'))
 $sm=[regex]::Match($timing,'SWNS:\s*(-?[0-9.]+)ns')
 $hm=[regex]::Match($timing,'HWNS:\s*(-?[0-9.]+)ns')
 if(-not $sm.Success -or -not $hm.Success){throw 'Final timing summary not recognized'}
 $info['bit']=$bit;$info['bitHash']=(Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash
 $info['setupWnsNs']=[double]$sm.Groups[1].Value;$info['holdWnsNs']=[double]$hm.Groups[1].Value
 $info['changedInputs']=@($inputs | Where-Object {(Get-FileHash -LiteralPath $_.Path -Algorithm SHA256).Hash -ne $_.Hash})
 if($info['changedInputs'].Count){throw 'Source files changed during build; inspect manifest'}
 if($info['setupWnsNs'] -lt 0 -or $info['holdWnsNs'] -lt 0){throw "Bit exists but final timing failed: $timing"}
 $info['status']='complete';$info['finished']=(Get-Date -Format o)
 Write-Output "PROJECT_BUILD_COMPLETE=$bit"
 Write-Output $timing
}catch{
 $info['status']='failed';$info['failure']=$_.Exception.Message
 throw
}finally{
 $info | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $record -Encoding UTF8
}
