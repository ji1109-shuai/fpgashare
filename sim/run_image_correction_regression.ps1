param([string]$VivadoRoot='D:/AMDDesignTools/2025.2/Vivado',
 [string]$BuildName='ae_field_markers_20261101_validation',
 [string]$CorrectionSource='')
$ErrorActionPreference='Stop'
$v=$VivadoRoot
$env:PATH="$v/lib/win64.o;$v/bin/unwrapped/win64.o;$v/tps/win64/jre21.0.5_11/bin/server;$v/tps/win64/jre21.0.5_11/bin;$v/tps/win64;"+$env:PATH
$env:XILINX_VIVADO=$v;$env:RDI_DATADIR="$v/data";$env:RDI_APPROOT=$v;$env:HDI_APPROOT=$v
$env:RDI_OPT_EXT='.o';$env:TCL_LIBRARY="$v/tps/tcl/tcl8.6";$env:RDI_LIBDIR="$v/lib/win64.o";$env:RDI_BINDIR="$v/bin";$env:RDI_PLATFORM='win64'
if(!$CorrectionSource){$CorrectionSource=Join-Path $PSScriptRoot '../user_source/hdl_source/image_correction.v'}
$CorrectionSource=(Resolve-Path -LiteralPath $CorrectionSource).Path
$build=Join-Path $PSScriptRoot $BuildName
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
 & "$v/bin/unwrapped/win64.o/xvlog.exe" -sv ../../user_source/hdl_source/isp/uial2axis.v $CorrectionSource ../tb_image_correction_markers.sv
 if($LASTEXITCODE -ne 0){throw 'RAW correction compile failed'}
 & "$v/bin/unwrapped/win64.o/xelab.exe" tb_image_correction_markers -s tb_image_correction_markers -timescale 1ns/1ps
 if($LASTEXITCODE -ne 0){throw 'RAW correction elaboration failed'}
 & "$v/bin/unwrapped/win64.o/xsim.exe" tb_image_correction_markers -runall -log tb_image_correction_markers.log
 $log=Get-Content tb_image_correction_markers.log -Raw
 if($LASTEXITCODE -ne 0 -or $log -notmatch 'ALL PASS' -or $log -match 'Fatal:|Error:|\bFAIL\b'){throw 'RAW correction simulation failed'}
}finally{Pop-Location}
