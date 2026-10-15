# Clock constraint for synthesis (syn/synth.tcl). 10 ns = 100 MHz target;
# the achievable frequency is computed from the worst setup slack:
#     Fmax = 1000 / (10 - WNS) MHz
create_clock -name clk -period 10.000 [get_ports clk]
