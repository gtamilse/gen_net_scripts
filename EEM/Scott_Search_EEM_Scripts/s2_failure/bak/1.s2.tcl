::cisco::eem::event_register_syslog pattern "CONFIG"

# Define the namespace
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

# Verify the environment vars:
if {![info exists _storage_location]} {
  set result "EEM policy error: environment var _storage_location not set"
  error $result $errInfo
}
if {![info exists _output_log]} {
  set result "EEM policy error: environment var _output_log not set"
  error $result $errInfo
}

global FH 

# Open the output file (for write):
if [catch {open $_storage_location/$_output_log w} result] {
    error $result
}
set FH $result

set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
puts $FH "*Timestamp = $date"

# Set node hostname:
set node [info hostname]
puts $FH "Node: $node"

set freq_list [sys_reqinfo_syslog_freq]
set hist_list [sys_reqinfo_syslog_history]
puts $FH $freq_list
foreach rec $hist_list {
     foreach syslog $rec {
         puts $FH $syslog
     }
}

close $FH

# Send syslog message:
action_syslog msg "EEM policy completed"
