param([string]$VivadoBin='D:/AMDDesignTools/2025.2/Vivado/bin',
      [string]$BuildName='video_modes_validation',
      [string[]]$Tops=@('tb_video_modes','tb_video_modes_onebeat','tb_video_modes_720p','tb_isp_video_modes','tb_video_mode_osd','tb_target_overlay','tb_video_tail_isp','tb_video_tail_isp_sobel'))
$ErrorActionPreference='Stop'
$vivado=Split-Path -Parent $VivadoBin
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
New-Item -ItemType Directory -Path $build -Force | Out-Null
Push-Location $build
try {
    $rtl='../../user_source/hdl_source'
    Copy-Item "$rtl/logo_idx.hex","$rtl/logo_pal.hex" -Destination . -Force
    & "$vivado/bin/unwrapped/win64.o/xvlog.exe" -sv "$rtl/img_video_modes.v" '../tb_video_modes.v' `
        "$rtl/img_proj.v" "$rtl/img_otsu.v" "$rtl/img_binarize.v" "$rtl/img_morph.v" "$rtl/img_bbox.v" "$rtl/img_roi.v" `
        "$rtl/isp/isp_top.v" "$rtl/isp/data128_96/data128_96.v" "$rtl/isp/data96_128/data96_128.v" `
        "$rtl/hdmi_mixer.v" "$rtl/osd_char_lib.v" "$rtl/design_top_wrapper.v" '../tb_isp_threshold.v' '../tb_isp_video_modes.v' '../tb_video_mode_osd.v' '../tb_target_overlay.v' `
        "$rtl/video_in.v" '../tb_video_modes_ddr.v' '../tb_video_tail.v'
    if($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
    foreach($top in $Tops) {
        & "$vivado/bin/unwrapped/win64.o/xelab.exe" $top -s $top -timescale 1ns/1ps
        if($LASTEXITCODE -ne 0) { throw "Elaboration failed: $top" }
        & "$vivado/bin/unwrapped/win64.o/xsim.exe" $top -runall -log "$top.log"
        $log=Get-Content -LiteralPath "$top.log" -Raw
        if($LASTEXITCODE -ne 0 -or $log -notmatch 'ALL PASS' -or $log -match 'Fatal:|Error:') { throw "Simulation failed: $top" }
    }
} finally { Pop-Location }
