param([string]$VivadoRoot='D:/AMDDesignTools/2025.2/Vivado',
    [string]$BuildName='ae_chain_raw_20261101_validation',
    [string[]]$Tops=@('tb_ae_raw_isp'),
    [string]$CorrectionSource='')
$ErrorActionPreference='Stop'
$v=$VivadoRoot
$env:PATH="$v/lib/win64.o;$v/bin/unwrapped/win64.o;$v/tps/win64/jre21.0.5_11/bin/server;$v/tps/win64/jre21.0.5_11/bin;$v/tps/win64;"+$env:PATH
$env:XILINX_VIVADO=$v;$env:RDI_DATADIR="$v/data";$env:RDI_APPROOT=$v;$env:HDI_APPROOT=$v
$env:RDI_OPT_EXT='.o';$env:TCL_LIBRARY="$v/tps/tcl/tcl8.6";$env:RDI_LIBDIR="$v/lib/win64.o";$env:RDI_BINDIR="$v/bin";$env:RDI_PLATFORM='win64'
$build=Join-Path $PSScriptRoot $BuildName
if(!$CorrectionSource){$CorrectionSource=Join-Path $PSScriptRoot '../user_source/hdl_source/image_correction.v'}
$CorrectionSource=(Resolve-Path -LiteralPath $CorrectionSource).Path
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
    $r='../../user_source/hdl_source';$d="$r/isp/demosaic_4x_2_0"
    & "$v/bin/unwrapped/win64.o/xvlog.exe" -sv "$r/awb.v" "$r/signal_delay.v" "$r/img_proj.v" `
        "$r/img_otsu.v" "$r/img_binarize.v" "$r/img_morph.v" "$r/img_bbox.v" "$r/img_roi.v" "$r/img_video_modes.v" `
        "$r/isp/isp_top.v" "$r/isp/data128_96/data128_96.v" "$r/isp/data96_128/data96_128.v" `
        "$d/demosaic.v" "$d/mipi_to_raw_converter.v" "$d/zhenghe.v" "$d/raw_matrix_3x3_buffer.v" `
        "$d/line_buffer_demosaic.v" "$d/bilinear_interpolation.v" ../tb_awb.v ../tb_ae_raw_isp.sv `
        "$r/uiisp_beta/ae_set.v" "$r/design_top_wrapper.v" "$r/uics500_cfg/uicfgcs500.v" `
        "$r/uics500_cfg/uics500reg.v" "$r/uics500_cfg/uics500regAE.v" "$r/uics500_cfg/uii2c.v" `
        "$r/uics500_cfg/SC500GainTbl.v" "$r/isp/csi_unpacket_2lane.v" `
        "$r/isp/raw10_unpacket_2lane.v" "$r/isp/uial2axis.v" $CorrectionSource ../tb_ae_chain.sv
    if($LASTEXITCODE -ne 0){throw 'RAW ISP compile failed'}
    foreach($top in $Tops){
        & "$v/bin/unwrapped/win64.o/xelab.exe" $top -s $top -timescale 1ns/1ps
        if($LASTEXITCODE -ne 0){throw "RAW ISP elaboration failed: $top"}
        & "$v/bin/unwrapped/win64.o/xsim.exe" $top -runall -log "$top.log"
        $log=Get-Content "$top.log" -Raw
        if($LASTEXITCODE -ne 0 -or $log -notmatch 'ALL PASS' -or $log -match 'Fatal:|Error:'){throw "RAW ISP simulation failed: $top"}
    }
}finally{Pop-Location}
