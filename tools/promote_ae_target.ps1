param([Parameter(Mandatory=$true)][string]$BuildRecord)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$runs=[IO.Path]::GetFullPath((Join-Path $repo 'td_project/camera_to_dsi_display_Runs'))
$recordPath=(Resolve-Path -LiteralPath $BuildRecord).Path
$record=Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
$evidence=Join-Path $repo 'sim/ae_target_20261101_validation'
$release=Join-Path $repo 'release_archive/ae_target_20261101'
$verified=Get-Content -LiteralPath (Join-Path $evidence 'verification.json') -Raw | ConvertFrom-Json
if($record.status -ne 'complete' -or $verified.status -ne 'verified_no_board_test' -or
   $verified.bitHash -ne $record.bitHash -or $verified.build.record -ne $recordPath){
 throw 'Only the fully verified AE3 target build can become the default run'
}
if(!(Test-Path -LiteralPath $release -PathType Container) -or
   !(Test-Path -LiteralPath (Join-Path $release 'camera_to_dsi_display_ae_target.bit'))){
 throw 'Archive the verified AE3 target release before changing default runs'
}
if((Get-FileHash -LiteralPath (Join-Path $release 'camera_to_dsi_display_ae_target.bit')).Hash -ne $record.bitHash){
 throw 'Archived AE3 target bit does not match the verified build'
}
if([IO.Path]::GetFullPath($record.project) -ne (Join-Path $repo 'td_project/camera_to_dsi_display.al')){
 throw 'Build belongs to another project'
}
foreach($item in $record.inputHashes){
 if((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.Hash){throw "Changed input: $($item.Path)"}
}
$syn=[IO.Path]::GetFullPath($record.synthesis)
$phy=[IO.Path]::GetFullPath($record.implementation)
foreach($source in @($syn,$phy)){
 if((Split-Path $source -Parent) -ne $runs -or (Split-Path $source -Leaf) -notmatch '^(syn|phy)_ae_target_r1_'){
  throw "Unexpected verified run path: $source"
 }
}
$defaultSyn=Join-Path $runs 'syn_1'
$defaultPhy=Join-Path $runs 'phy_1'
foreach($target in @($defaultSyn,$defaultPhy)){
 $resolved=(Resolve-Path -LiteralPath $target).Path
 if((Split-Path $resolved -Parent) -ne $runs -or (Get-Item -LiteralPath $target -Force).LinkType){
  throw "Default run target is not a plain directory within this project's Runs: $target"
 }
}
if(@(Get-CimInstance Win32_Process -Filter "Name='td_commands_prompt.exe'").Count){
 throw 'A TD command session is still active; default runs were not replaced'
}
$bitName='camera_to_dsi_display.bit'
$originalBit=Join-Path $defaultPhy $bitName
$originalHash=(Get-FileHash -LiteralPath $originalBit -Algorithm SHA256).Hash
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$savedSyn=Join-Path $runs "syn_1_before_ae_target_$stamp"
$savedPhy=Join-Path $runs "phy_1_before_ae_target_$stamp"
if((Test-Path -LiteralPath $savedSyn) -or (Test-Path -LiteralPath $savedPhy)){throw 'Backup target exists'}
$synMoved=$false;$phyMoved=$false
try{
 # Native moves stay inside the checked Runs directory and preserve old data.
 Move-Item -LiteralPath $defaultSyn -Destination $savedSyn
 $synMoved=$true
 Move-Item -LiteralPath $defaultPhy -Destination $savedPhy
 $phyMoved=$true
 Copy-Item -LiteralPath $syn -Destination $defaultSyn -Recurse
 Copy-Item -LiteralPath $phy -Destination $defaultPhy -Recurse
 # Future GUI builds must follow their actual default synthesis run too.
 $settingsPath=Join-Path $defaultPhy 'settings.cfg'
 $settings=[IO.File]::ReadAllText($settingsPath)
 if($settings -notmatch '(?m)^set parent .*$'){throw 'Copied physical settings have no synthesis parent'}
 $settings=[regex]::Replace($settings,'(?m)^set parent .*$', 'set parent ../syn_1')
 [IO.File]::WriteAllText($settingsPath,$settings,(New-Object Text.UTF8Encoding($false)))
 $defaultBit=Join-Path $defaultPhy $bitName
 $actualHash=(Get-FileHash -LiteralPath $defaultBit -Algorithm SHA256).Hash
 if($actualHash -ne $record.bitHash){throw 'Default bit differs from the verified artifact'}
 foreach($file in @('camera_to_dsi_display_gate.db')){
  if((Get-FileHash -LiteralPath (Join-Path $syn $file)).Hash -ne
     (Get-FileHash -LiteralPath (Join-Path $defaultSyn $file)).Hash){throw "Synthesis copy mismatch: $file"}
 }
 foreach($file in @('final_timing.rpt','camera_to_dsi_display_phy.ts','camera_to_dsi_display_phy.area','route_flow.status')){
  if((Get-FileHash -LiteralPath (Join-Path $phy $file)).Hash -ne
     (Get-FileHash -LiteralPath (Join-Path $defaultPhy $file)).Hash){throw "Physical report copy mismatch: $file"}
 }
 $info=[ordered]@{promoted=(Get-Date -Format o);buildRecord=$recordPath;bitHash=$actualHash;
  defaultBit=$defaultBit;defaultSynthesis=$defaultSyn;defaultImplementation=$defaultPhy;
  sourceSynthesis=$syn;sourceImplementation=$phy;previousDefaultBitHash=$originalHash;
  previousSynthesisBackup=$savedSyn;previousImplementationBackup=$savedPhy;
  parentSetting='set parent ../syn_1';boardProgrammed=$false}
 $info | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'default_run_promotion.json') -Encoding UTF8
 Copy-Item -LiteralPath (Join-Path $evidence 'default_run_promotion.json') -Destination $release
 $info | ConvertTo-Json -Depth 4
}catch{
 # Keep any partial copy for diagnosis; never delete or discard the old runs.
 if($phyMoved){
  if(Test-Path -LiteralPath $defaultPhy){Move-Item -LiteralPath $defaultPhy -Destination (Join-Path $runs "phy_1_partial_ae_target_$stamp")}
  Move-Item -LiteralPath $savedPhy -Destination $defaultPhy
 }
 if($synMoved){
  if(Test-Path -LiteralPath $defaultSyn){Move-Item -LiteralPath $defaultSyn -Destination (Join-Path $runs "syn_1_partial_ae_target_$stamp")}
  Move-Item -LiteralPath $savedSyn -Destination $defaultSyn
 }
 throw
}
