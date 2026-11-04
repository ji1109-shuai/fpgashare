param([Parameter(Mandatory=$true)][string]$PreviousRecord,[string]$Tag='ui_overlay_r2',[string]$Strategy='TimingUltra')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$runs=Join-Path $repo 'td_project/camera_to_dsi_display_Runs'
$previous=Get-Content -LiteralPath $PreviousRecord -Raw | ConvertFrom-Json
foreach($item in $previous.inputHashes){if((Get-FileHash -LiteralPath $item.Path).Hash -ne $item.Hash){throw "Changed synthesis input: $($item.Path)"}}
if([IO.Path]::GetFullPath($previous.project) -ne (Join-Path $repo 'td_project/camera_to_dsi_display.al')){throw 'Wrong source project'}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$phy=Join-Path $runs ('phy_'+$Tag+'_'+$stamp)
$record=Join-Path $runs ($Tag+'_build_'+$stamp+'.json')
New-Item -ItemType Directory $phy | Out-Null
$previousPhy=$previous.implementation
Copy-Item -LiteralPath (Join-Path $previousPhy 'camera_to_dsi_display.prj') -Destination $phy
$settings=[IO.File]::ReadAllText((Join-Path $previousPhy 'settings.cfg'))
$strategies=Get-Content -LiteralPath 'D:/AN_LU/doc/strategies/official_strategy_ph1.json' -Raw | ConvertFrom-Json
$chosen=$strategies.$Strategy
if(-not $chosen -or $chosen.is_syn -ne 'phy'){throw 'Unknown official physical strategy'}
$paramWords=@($chosen.params | ForEach-Object {"$($_.step) $($_.param) $($_.val)"}) -join ' '
$settings+=[Environment]::NewLine+'set phyWildParams {'+$paramWords+'}'+[Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $phy 'settings.cfg'),$settings,(New-Object Text.UTF8Encoding($false)))
foreach($asset in @('industrial_font16.hex','logo_idx.hex','logo_pal.hex')){Copy-Item -LiteralPath (Join-Path $previousPhy $asset) -Destination $phy}
$info=[ordered]@{project=$previous.project;started=(Get-Date -Format o);synthesis=$previous.synthesis;implementation=$phy;inputHashes=$previous.inputHashes;status='running';synthesisReusedFrom=[IO.Path]::GetFullPath($PreviousRecord);physicalStrategy=$Strategy;physicalParameters=$chosen.params;physicalSettingsHash=(Get-FileHash -LiteralPath (Join-Path $phy 'settings.cfg')).Hash}
$info | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $record -Encoding UTF8
Write-Output "BUILD_RECORD=$record"
try{
 Push-Location $phy
 try{& 'D:/AN_LU/bin/td_commands_prompt.exe' 'D:/AN_LU/doc/scripts/DefaultFlow.tcl';if($LASTEXITCODE -ne 0){throw 'TD implementation process failed'}}finally{Pop-Location}
 $log=Get-ChildItem -LiteralPath $phy -Filter 'td_*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
 if(-not $log){throw 'Missing TD log'}
 if(Select-String -LiteralPath $log.FullName -Pattern '\b[A-Z]+-[0-9]+\s+(ERROR|FATAL)\b'){throw 'TD implementation errors'}
 $bit=Join-Path $phy 'camera_to_dsi_display.bit'
 $timing=[IO.File]::ReadAllText((Join-Path $phy 'camera_to_dsi_display_phy.ts'))
 $sm=[regex]::Match($timing,'SWNS:\s*(-?[0-9.]+)ns');$hm=[regex]::Match($timing,'HWNS:\s*(-?[0-9.]+)ns')
 if(-not $sm.Success -or -not $hm.Success){throw 'Unrecognized final timing'}
 $info['bit']=$bit;$info['bitHash']=(Get-FileHash -LiteralPath $bit).Hash;$info['setupWnsNs']=[double]$sm.Groups[1].Value;$info['holdWnsNs']=[double]$hm.Groups[1].Value
 $info['changedInputs']=@($info.inputHashes | Where-Object {(Get-FileHash -LiteralPath $_.Path).Hash -ne $_.Hash})
 if($info.changedInputs.Count){throw 'Changed production inputs'}
 if($info.setupWnsNs -lt 0 -or $info.holdWnsNs -lt 0){throw "Final timing failed: $timing"}
 $info['status']='complete';$info['finished']=(Get-Date -Format o)
 Write-Output "PROJECT_BUILD_COMPLETE=$bit"
 Write-Output $timing
}catch{$info['status']='failed';$info['failure']=$_.Exception.Message;throw}finally{$info | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $record -Encoding UTF8}
