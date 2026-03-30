///////////////////////////////////////////////////////////////////////////////
// rmii_mii_config.sv
///////////////////////////////////////////////////////////////////////////////
// Configuration object for the rmii_to_mii UVM testbench.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_MII_CONFIG_SV
`define GUARD_RMII_MII_CONFIG_SV

class rmii_mii_config extends uvm_object;

  // Clock period for the 50 MHz RMII reference clock (ns)
  int unsigned ref_clk_period = 20;

  `uvm_object_utils_begin(rmii_mii_config)
    `uvm_field_int(ref_clk_period, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "rmii_mii_config");
    super.new(name);
  endfunction

endclass

`endif // GUARD_RMII_MII_CONFIG_SV
