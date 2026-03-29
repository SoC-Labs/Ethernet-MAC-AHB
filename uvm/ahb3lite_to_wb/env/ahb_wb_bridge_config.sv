///////////////////////////////////////////////////////////////////////////////
// ahb_wb_bridge_config.sv
///////////////////////////////////////////////////////////////////////////////
// Customized SVT AHB system configuration for the ahb3lite_to_wb testbench.
//
// The DUT is the AHB slave, so:
//   - VIP master[0] is ACTIVE  (drives AHB master stimulus to DUT)
//   - No VIP slave needed      (DUT is the AHB slave)
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WB_BRIDGE_CONFIG_SV
`define GUARD_AHB_WB_BRIDGE_CONFIG_SV

class ahb_wb_bridge_config extends svt_ahb_system_configuration;

  `uvm_object_utils(ahb_wb_bridge_config)

  function new(string name = "ahb_wb_bridge_config");
    super.new(name);

    // 1 active master (VIP drives AHB stimulus), 1 slave (DUT itself)
    this.num_masters = 1;
    this.num_slaves  = 1;

    this.create_sub_cfgs(1, 1);

    // Master is active -- VIP drives AHB master signals to the DUT
    this.master_cfg[0].is_active = 1;
    this.master_cfg[0].data_width = 32;
    this.master_cfg[0].transaction_coverage_enable = 1;

    // Slave is passive -- DUT is the AHB slave, VIP only monitors
    this.slave_cfg[0].is_active = 0;
    this.slave_cfg[0].data_width = 32;
    this.slave_cfg[0].transaction_coverage_enable = 1;

    // AHB-Lite mode (no arbiter, no split/retry)
    this.ahb_lite = 1;

    // Slave responds to the full address range
    this.set_addr_range(0, 32'h0000_0000, 32'hFFFF_FFFF);

    // Disable protocol file generation
    this.master_cfg[0].enable_xml_gen = 0;
    this.slave_cfg[0].enable_xml_gen  = 0;
  endfunction

endclass

`endif // GUARD_AHB_WB_BRIDGE_CONFIG_SV
