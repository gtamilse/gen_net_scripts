::cisco::eem::event_register_none maxrun_sec 180

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*


####################
# MAIN
####################
global FH
set LCs ""

# Capture start time:
set time_now [clock seconds]
set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

set filename "test_eem.$date_time"
set output_file "disk0:/eem/$filename"

# Open the output file (for write):
if [catch {open $output_file w} result] {
    error $result
}
set FH $result

# Timestamp start time to the output log file:
puts $FH "Start Timestamp: $date"

set result [cli "show module"]
puts $FH "OUTPUT:\n$result"

set result [cli "show redundancy"]
puts $FH "OUTPUT:\n$result"

