param([string]$VivadoRoot='D:/AMDDesignTools/2025.2/Vivado',
 [string]$BuildName='ae_chain_20261101_validation',
 [string]$SensorConfigSource='',
 [string]$AeSource='',
 [string[]]$Tops=@('tb_ae_meter','tb_ae_chain','tb_ae_chain_dark','tb_ae_chain_midlight','tb_ae_chain_extreme','tb_ae_chain_motor','tb_ae_chain_nack','tb_ae_chain_boot_nack'))
$ErrorActionPreference='Stop'
$v=$VivadoRoot
$env:PATH="$v/lib/win64.o;$v/bin/unwrapped/win64.o;$v/tps/win64/jre21.0.5_11/bin/server;$v/tps/win64/jre21.0.5_11/bin;$v/tps/win64;"+$env:PATH
$env:XILINX_VIVADO=$v;$env:RDI_DATADIR="$v/data";$env:RDI_APPROOT=$v;$env:HDI_APPROOT=$v
$env:RDI_OPT_EXT='.o';$env:TCL_LIBRARY="$v/tps/tcl/tcl8.6";$env:RDI_LIBDIR="$v/lib/win64.o";$env:RDI_BINDIR="$v/bin";$env:RDI_PLATFORM='win64'
$build=Join-Path $PSScriptRoot $BuildName
if(!$SensorConfigSource){$SensorConfigSource=Join-Path $PSScriptRoot '../user_source/hdl_source/uics500_cfg/uicfgcs500.v'}
$SensorConfigSource=(Resolve-Path -LiteralPath $SensorConfigSource).Path
if(!$AeSource){$AeSource=Join-Path $PSScriptRoot '../user_source/hdl_source/uiisp_beta/ae_set.v'}
$AeSource=(Resolve-Path -LiteralPath $AeSource).Path
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
 $r='../../user_source/hdl_source'
 & "$v/bin/unwrapped/win64.o/xvlog.exe" -sv $AeSource "$r/isp/isp_top.v" "$r/design_top_wrapper.v" $SensorConfigSource "$r/uics500_cfg/uics500reg.v" "$r/uics500_cfg/uics500regAE.v" "$r/uics500_cfg/uii2c.v" "$r/uics500_cfg/SC500GainTbl.v" ../tb_ae_chain.sv
 if($LASTEXITCODE -ne 0){throw 'Real AE chain compile failed'}
 foreach($top in $Tops){
  & "$v/bin/unwrapped/win64.o/xelab.exe" $top -s $top -timescale 1ns/1ps
  if($LASTEXITCODE -ne 0){throw "Real AE chain elaboration failed: $top"}
  & "$v/bin/unwrapped/win64.o/xsim.exe" $top -runall -log "$top.log"
  $log=Get-Content "$top.log" -Raw
  if($LASTEXITCODE -ne 0 -or $log -notmatch 'ALL PASS' -or $log -match 'Fatal:|Error:|\bFAIL\b'){throw "Real AE chain simulation failed: $top"}
 }
}finally{Pop-Location}
