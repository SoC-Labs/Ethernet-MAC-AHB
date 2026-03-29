///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_config.sv
///////////////////////////////////////////////////////////////////////////////
// Customized SVT AHB system configuration for the wb_to_ahb3lite testbench.
//
// The DUT is the AHB master, so:
//   - VIP master[0] is PASSIVE (monitor only, observes DUT's AHB outputs)
//   - VIP slave[0]  is ACTIVE  (responds to DUT's AHB master requests)
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_CONFIG_SV
`define GUARD_WB_AHB_BRIDGE_CONFIG_SV

class wb_ahb_bridge_config extends svt_ahb_system_configuration;

  `uvm_object_utils(wb_ahb_bridge_config)

  function new(string name = "wb_ahb_bridge_config");
    super.new(name);

    // 1 passive master (DUT is the real master), 1 active slave
    this.num_masters = 1;
    this.num_slaves  = 1;

    this.create_sub_cfgs(1, 1);

    // Master is passive -- DUT drives the AHB master signals
    this.master_cfg[0].is_active = 0;
    this.master_cfg[0].data_width = 32;
    this.master_cfg[0].transaction_coverage_enable = 1;

    // Slave is active -- VIP drives responses (hrdata, hresp, hready)
    this.slave_cfg[0].is_active = 1;
    this.slave_cfg[0].data_width = 32;
    this.slave_cfg[0].transaction_coverage_enable = 1;

    // AHB-Lite mode (no arbiter, no split/retry)
    this.ahb_lite = 1;

    // Slave responds to the full address range
    this.set_addr_range(0, 32'h0000_0000, 32'hFFFF_FFFF);

    // Enable protocol file generation for Protocol Analyzer
    this.master_cfg[0].enable_xml_gen = 0;
    this.slave_cfg[0].enable_xml_gen  = 0;
  endfunction

endclass

`endif // GUARD_WB_AHB_BRIDGE_CONFIG_SV
