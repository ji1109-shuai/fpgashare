param([string]$VivadoRoot='D:/AMDDesignTools/2025.2/Vivado',
      [string]$BuildName='ae_once_20261101_validation',
      [string[]]$Tops=@('tb_ae_once','tb_ae_once_single','tb_ae_menu_status','tb_ae_menu_status_rd2','tb_tracker_speed_boundary','tb_screen_menu','tb_batch_counter'),
      [string]$TopSource='')
$ErrorActionPreference='Stop'
$vivado=$VivadoRoot
$env:PATH="$vivado/lib/win64.o;$vivado/bin/unwrapped/win64.o;$vivado/tps/win64/jre21.0.5_11/bin/server;$vivado/tps/win64/jre21.0.5_11/bin;$vivado/tps/win64;"+$env:PATH
$env:XILINX_VIVADO=$vivado
$env:RDI_DATADIR="$vivado/data";$env:RDI_APPROOT=$vivado;$env:HDI_APPROOT=$vivado
$env:RDI_OPT_EXT='.o';$env:TCL_LIBRARY="$vivado/tps/tcl/tcl8.6"
$env:RDI_LIBDIR="$vivado/lib/win64.o";$env:RDI_BINDIR="$vivado/bin";$env:RDI_PLATFORM='win64'
$build=Join-Path $PSScriptRoot $BuildName
if(!$TopSource){$TopSource=Join-Path $PSScriptRoot '../user_source/hdl_source/design_top_wrapper.v'}
$TopSource=(Resolve-Path -LiteralPath $TopSource).Path
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
 $rtl='../../user_source/hdl_source'
 Copy-Item "$rtl/logo_idx.hex","$rtl/logo_pal.hex" -Destination . -Force
    Copy-Item (Join-Path $PSScriptRoot "../user_source/hdl_source/industrial_font16.hex") -Destination . -Force
 & "$vivado/bin/unwrapped/win64.o/xvlog.exe" -sv "$rtl/uiisp_beta/ae_set.v" "$rtl/hdmi_mixer.v" "$rtl/osd_char_lib.v" "$rtl/img_proj.v" $TopSource ../tb_ae_once.sv ../tb_ae_menu_status.sv ../tb_tracker_speed_boundary.sv ../tb_screen_menu.v ../tb_batch_counter.v ../tb_ae_boot_keys.sv ../tb_ae_target.sv
 if($LASTEXITCODE -ne 0){throw 'AE compile failed'}
 foreach($top in $Tops) {
  & "$vivado/bin/unwrapped/win64.o/xelab.exe" $top -s $top -timescale 1ns/1ps
  if($LASTEXITCODE -ne 0){throw "AE elaboration failed: $top"}
  & "$vivado/bin/unwrapped/win64.o/xsim.exe" $top -runall -log "$top.log"
  $log=Get-Content -LiteralPath "$top.log" -Raw
  if($LASTEXITCODE -ne 0 -or $log -notmatch 'ALL PASS|TB_PASS screen_menu_control|PASS: simultaneous counting, overrun stop and reject recovery' -or $log -match 'Fatal:|Error:|TB_FAIL|\bFAIL\b') {
   throw "AE simulation failed: $top"
  }
 }
} finally {Pop-Location}
