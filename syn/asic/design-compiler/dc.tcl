#-----------------------------------------------------------------------------
# Synopsys Design Compiler TCL script for Ethernet MAC AHB
#
# Usage: make -C syn/asic/design-compiler syn MODULE=ethmac_ahb
#
# Environment variables (set by Makefile via common.mk):
#   ETHMAC_AHB_HOME - Root of the Ethernet MAC AHB repository
#   MODULE          - Top-level module name
#   FLIST           - Path to the filelist
#   TARGET_LIB      - Target cell library (.db)
#   LINK_LIBS       - Link libraries
#   CLK_NAME        - Clock port name
#   CLK_PERIOD      - Clock period (ns)
#   RST_NAME        - Reset port name
#-----------------------------------------------------------------------------

set ethmac_ahb_home $::env(ETHMAC_AHB_HOME)
set top_module      $::env(MODULE)
set flist           $::env(FLIST)
set target_lib      $::env(TARGET_LIB)
set link_libs       $::env(LINK_LIBS)
set clk_name        $::env(CLK_NAME)
set clk_period      $::env(CLK_PERIOD)
set rst_name        $::env(RST_NAME)

# ── Library setup ──────────────────────────────────────────────────────────
set_app_var target_library $target_lib
set_app_var link_library   "* $link_libs"
set_app_var search_path    "$ethmac_ahb_home/src/rtl"

# ── Read design ────────────────────────────────────────────────────────────
set_svf ${top_module}.svf

# Helper: expand ${VAR} references to environment variable values
proc expand_env {str} {
    while {[regexp {\$\{(\w+)\}} $str -> varname]} {
        if {[info exists ::env($varname)]} {
            set pattern "\\$\\{${varname}\\}"
            regsub $pattern $str $::env($varname) str
        } else {
            error "Environment variable $varname is not set"
        }
    }
    return $str
}

# Read and process the filelist
set fh [open $flist r]
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
        # Skip empty lines and comments
        continue
    } elseif {[string match "+incdir+*" $line]} {
        # Handle include directory
        set incdir [expand_env [string range $line 8 end]]
        set_app_var search_path [concat [get_app_var search_path] $incdir]
    } elseif {[string match "+define+*" $line]} {
        # Handle defines — skip for DC (handled via filelist conventions)
        continue
    } else {
        # Process file (substitute environment variables)
        set file [expand_env $line]
        if {[string match "*.sv" $file]} {
            analyze -format sverilog $file
        } elseif {[string match "*.v" $file]} {
            analyze -format verilog $file
        }
    }
}
close $fh

elaborate $top_module
current_design $top_module
link

# ── Design constraints ─────────────────────────────────────────────────────
create_clock -name $clk_name -period $clk_period [get_ports $clk_name]
set_clock_uncertainty 0.1 [get_clocks $clk_name]

# Reset: treat as asynchronous, don't time it
set_false_path -from [get_ports $rst_name]

# Additional clock: rtc_clk (present on ethmac_subsystem_apb)
# Asynchronous to the main APB clock — constrain separately with false paths
set has_rtc_clk [sizeof_collection [get_ports rtc_clk -quiet]]
if {$has_rtc_clk > 0} {
    create_clock -name rtc_clk -period $clk_period [get_ports rtc_clk]
    set_clock_uncertainty 0.1 [get_clocks rtc_clk]
    set_false_path -from [get_clocks $clk_name] -to [get_clocks rtc_clk]
    set_false_path -from [get_clocks rtc_clk]   -to [get_clocks $clk_name]
    puts "INFO: Created async clock rtc_clk with false paths to $clk_name"
}

# Input/output delays (25% of clock period as default estimate)
set io_delay [expr {$clk_period * 0.25}]
set exclude_ports [list $clk_name $rst_name]
if {$has_rtc_clk > 0} { lappend exclude_ports rtc_clk }
set all_inputs  [remove_from_collection [all_inputs] [get_ports $exclude_ports]]
set all_outputs [all_outputs]

set_input_delay  -clock $clk_name $io_delay $all_inputs
set_output_delay -clock $clk_name $io_delay $all_outputs

# Drive and load estimates
if {[llength $all_inputs] > 0} {
    set_driving_cell -no_design_rule -library [file rootname [file tail $target_lib]] \
        -pin Z $all_inputs
}
set_load 0.01 $all_outputs

# ── Compile ────────────────────────────────────────────────────────────────
check_design
compile_ultra

# ── Reports ────────────────────────────────────────────────────────────────
set rpt_dir "${top_module}_dc_reports"
file mkdir $rpt_dir

report_timing    -max_paths 20    > ${rpt_dir}/timing.rpt
report_area      -hierarchy       > ${rpt_dir}/area.rpt
report_power     -hierarchy       > ${rpt_dir}/power.rpt
report_qor                        > ${rpt_dir}/qor.rpt
report_design                     > ${rpt_dir}/design.rpt
report_constraints -all_violators > ${rpt_dir}/constraints.rpt
report_cell                       > ${rpt_dir}/cells.rpt
report_reference -hierarchy       > ${rpt_dir}/references.rpt

# ── Activity-based power (optional SAIF) ──────────────────────────────────
# If SAIF_FILE is set, read switching activity and produce a separate report
if {[info exists ::env(SAIF_FILE)] && $::env(SAIF_FILE) ne ""} {
    set saif_file $::env(SAIF_FILE)
    if {[file exists $saif_file]} {
        puts "INFO: Reading SAIF file: $saif_file"
        reset_switching_activity
        read_saif -input $saif_file -instance_name tb_top/u_dut
        report_power -hierarchy > ${rpt_dir}/power_saif.rpt
        puts "INFO: Activity-based power report written to ${rpt_dir}/power_saif.rpt"
    } else {
        puts "WARNING: SAIF file not found: $saif_file"
    }
}

# ── Write outputs ──────────────────────────────────────────────────────────
set out_dir "${top_module}_dc_output"
file mkdir $out_dir

write -format verilog -hierarchy -output ${out_dir}/${top_module}.mapped.v
write -format ddc     -hierarchy -output ${out_dir}/${top_module}.ddc
write_sdc                                ${out_dir}/${top_module}.sdc
write_sdf                                ${out_dir}/${top_module}.sdf

puts "INFO: Design Compiler synthesis complete for ${top_module}"
puts "INFO: Reports  written to ${rpt_dir}/"
puts "INFO: Netlists written to ${out_dir}/"

# Exit unless GUI mode is requested
if { ![info exists ::env(DC_GUI)] || $::env(DC_GUI) != "1" } {
    exit
}
