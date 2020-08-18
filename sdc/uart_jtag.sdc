# set this to whatever the jtag clock rate is
# the following command will provide this number 
# >> jtagconfig -d 
create_clock -name {altera_reserved_tck} -period 41.667 [get_ports { altera_reserved_tck }]