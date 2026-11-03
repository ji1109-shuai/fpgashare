param([string]$BuildName='colour_stability_validation',
    [string]$VivadoRoot='D:/AMDDesignTools/2025.2/Vivado',
    [string[]]$Tops=@('tb_awb_auto_reference','tb_bayer_neutral','tb_auto_wb_isp','tb_auto_wb_overlay','tb_colour_ratios','tb_wb_reference','tb_colour_diagnostic_osd','tb_colour_diagnostic_raster','tb_colour_stream_error','tb_awb','tb_wb_invalid','tb_wb_probe','tb_wb_probe_overlay','tb_multi_overlay','tb_wb_probe_isp'))
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
$build=Join-Path $PSScriptRoot $BuildName
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
    $rtl='../../user_source/hdl_source'
    Copy-Item "$rtl/logo_idx.hex","$rtl/logo_pal.hex" -Destination . -Force
    Copy-Item (Join-Path $PSScriptRoot "../user_source/hdl_source/industrial_font16.hex") -Destination . -Force
    & "$vivado/bin/unwrapped/win64.o/xvlog.exe" -sv "$rtl/uiisp_beta/ae_set.v" `
        "$rtl/uics500_cfg/uicfgcs500.v" "$rtl/uics500_cfg/uics500reg.v" `
        "$rtl/uics500_cfg/uics500regAE.v" "$rtl/uics500_cfg/SC500GainTbl.v" `
        "$rtl/uics500_cfg/uii2c.v" "$rtl/hdmi_mixer.v" "$rtl/osd_char_lib.v" `
        "$rtl/img_proj.v" "$rtl/awb.v" "$rtl/signal_delay.v" `
        "$rtl/img_otsu.v" "$rtl/img_binarize.v" "$rtl/img_morph.v" "$rtl/img_bbox.v" "$rtl/img_roi.v" "$rtl/img_video_modes.v" `
        "$rtl/isp/isp_top.v" "$rtl/isp/data128_96/data128_96.v" "$rtl/isp/data96_128/data96_128.v" "$rtl/design_top_wrapper.v" `
        '../tb_awb.v' '../tb_colour_stability.v' '../tb_colour_diagnostic_raster.v' '../tb_wb_invalid.v' `
        '../tb_wb_probe.v' '../tb_multi_overlay.v' '../tb_wb_probe_isp.v' '../tb_awb_auto_reference.v' `
        "$rtl/isp/demosaic_4x_2_0/bilinear_interpolation.v" '../tb_bayer_neutral.v' '../tb_auto_wb_isp.v'
    if($LASTEXITCODE -ne 0){throw 'Camera control compilation failed'}
    foreach($top in $Tops){
        & "$vivado/bin/unwrapped/win64.o/xelab.exe" $top -s $top -timescale 1ns/1ps
        if($LASTEXITCODE -ne 0){throw "Elaboration failed: $top"}
        & "$vivado/bin/unwrapped/win64.o/xsim.exe" $top -runall -log "$top.log"
        $result=Get-Content "$top.log" -Raw
        if($LASTEXITCODE -ne 0 -or $result -notmatch 'ALL PASS' -or $result -match 'Fatal:|Error:'){
            throw "Simulation failed: $top"
        }
    }
} finally {Pop-Location}
