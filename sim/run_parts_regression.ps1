param([string]$VivadoRoot='D:/AMDDesignTools/2025.2/Vivado',
    [string]$ProjectionSource='',
    [string[]]$Tops=@('tb_parts_color_hsv','tb_parts_shape_pipeline','tb_parts','tb_parts_colours','tb_parts_multi_no_calibration','tb_parts_ambient_shadows','tb_parts_solid_rejection','tb_parts_clean_overlay','tb_box_tracking','tb_batch_counter','tb_recognition_latency','tb_parts_multi_latency','tb_latency_overlay'),
    [string]$BuildName='parts_validation')
$ErrorActionPreference='Stop'
$vivado=$VivadoRoot
$env:PATH="$vivado/lib/win64.o;$vivado/bin/unwrapped/win64.o;$vivado/tps/win64/jre21.0.5_11/bin/server;$vivado/tps/win64/jre21.0.5_11/bin;$vivado/tps/win64;"+$env:PATH
$env:XILINX_VIVADO=$vivado
$env:RDI_DATADIR="$vivado/data"
$env:RDI_APPROOT=$vivado
$env:HDI_APPROOT=$vivado
$env:RDI_OPT_EXT='.o'
$env:TCL_LIBRARY="$vivado/tps/tcl/tcl8.6"
$env:RDI_LIBDIR="$vivado/lib/win64.o"
$env:RDI_BINDIR="$vivado/bin"
$env:RDI_PLATFORM='win64'
if(!$ProjectionSource){$ProjectionSource=Join-Path $PSScriptRoot '../user_source/hdl_source/img_proj.v'}
$ProjectionSource=(Resolve-Path -LiteralPath $ProjectionSource).Path
$build=Join-Path $PSScriptRoot $BuildName
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
 Copy-Item ../../user_source/hdl_source/logo_idx.hex,../../user_source/hdl_source/logo_pal.hex -Destination . -Force
    Copy-Item (Join-Path $PSScriptRoot "../user_source/hdl_source/industrial_font16.hex") -Destination . -Force
 & "$vivado/bin/unwrapped/win64.o/xvlog.exe" -sv $ProjectionSource ../../user_source/hdl_source/design_top_wrapper.v ../tb_parts_color_hsv.v ../tb_parts.v ../tb_parts_shape_pipeline.v ../tb_parts_multi.v ../../user_source/hdl_source/hdmi_mixer.v ../../user_source/hdl_source/osd_char_lib.v ../tb_multi_overlay.v ../tb_box_tracking.v ../tb_batch_counter.v ../tb_recognition_latency.v ../tb_latency_overlay.v
 if($LASTEXITCODE -ne 0){throw 'Parts compile failed'}
 foreach($top in $Tops){
 & "$vivado/bin/unwrapped/win64.o/xelab.exe" $top -s $top -timescale 1ns/1ps
 if($LASTEXITCODE -ne 0){throw 'Parts elaboration failed'}
 & "$vivado/bin/unwrapped/win64.o/xsim.exe" $top -runall -log "$top.log"
 $result=Get-Content "$top.log" -Raw
 if($LASTEXITCODE -ne 0 -or $result -notmatch 'ALL PASS' -or $result -match 'Fatal:|Error:'){throw 'Parts simulation failed'}
 }
} finally {Pop-Location}
