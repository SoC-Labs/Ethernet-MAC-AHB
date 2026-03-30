import cocotb
from cocotb.triggers import RisingEdge, Timer

@cocotb.test()
async def test_clk_debug(dut):
    from test_ethmac_ahb import EthmacAhbTB, HAS_COCOTBEXT_ETH
    tb = EthmacAhbTB(dut)
    log = dut._log
    
    # Let the system run for a bit
    await Timer(200, "ns")
    
    # Sample mtx_clk_pad_i at various times
    for i in range(20):
        await Timer(5, "ns")
        try:
            v = int(dut.mtx_clk_pad_i.value)
            log.info("t=%dns: mtx_clk_pad_i=%d", 200 + i*5, v)
        except:
            log.info("t=%dns: mtx_clk_pad_i=X", 200 + i*5)
    
    # Wait for rising edges of mtx_clk_pad_i
    log.info("Waiting for mtx_clk_pad_i rising edges...")
    for i in range(5):
        await RisingEdge(dut.mtx_clk_pad_i)
        t = cocotb.utils.get_sim_time("ns")
        log.info("mtx_clk_pad_i rising edge at %.1fns", t)
