::cisco::eem::event_register_syslog occurs 3 period 10 pattern "fabricq_mgr.*FABRIC-FABRICQ-3-RESET : Reseting Fabricq ASIC Device.*Reason: UC_PSN_WRAP"

# Define the namespace
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
##########################################################################################
# Set the pattern the script will filter on (maybe set within the eem environment vars):
##########################################################################################
set pattern "fabricq_mgr.*FABRIC-FABRICQ-3-RESET : Reseting Fabricq ASIC Device.*Reason: UC_PSN_WRAP"

##################################
# Verify the environment vars:
##################################
# Storage location:
if {![info exists _s2FailDetect_storage_location]} {
  set result "EEM policy error: environment var _s2FailDetect_storage_location not set"
  error $result $errInfo
}
# Output log file:
if {![info exists _s2FailDetect_output_log]} {
  set result "EEM policy error: environment var _s2FailDetect_output_log not set"
  error $result $errInfo
}
# Seconds difference, used for comparing previous matched syslogs:
if {![info exists _s2FailDetect_second_diff]} {
  set result "EEM policy error: environment var _s2FailDetect_second_diff not set"
  error $result $errInfo
}
# Unique locations for comparing:
if {![info exists _s2FailDetect_unique_locations]} {
  set result "EEM policy error: environment var _s2FailDetect_unique_locations not set"
  error $result $errInfo
}
# Nodes Router ospf process:
if {![info exists _s2FailDetect_ospf_id]} {
  set result "EEM policy error: environment var _s2FailDetect_ospf_id not set"
  error $result $errInfo
}


##################################
# PROCs:
##################################
proc extract_location {line} {
  global FH
  set location ""

  # Trim up the line remove extra space/tabs etc:
  regsub -all {[ \r\t\n]+} $line " " line
  # Remove any leading white space:
  regsub -all {^[ ]} $line "" line
  # Remove any ending white space:
  regsub -all {[ ]$} $line "" line

  if {[regexp {^time_sec} $line]} {
    regexp "\{(.*): .*" $line - msg
    set location [ lindex [split $msg ":"] 0 ]
    puts $FH "Location Extracted: $location\n"
  } else {
    set location [ lindex [split $line ":"] 0 ]
    puts $FH "Location Extracted: $location\n"
  }
  return $location
}


##################################
# Main/main
##################################
global FH
set locations ""

# Open the output file (for write):
if [catch {open $_s2FailDetect_storage_location/$_s2FailDetect_output_log w} result] {
    error $result
}
set FH $result

# Capture the scripts start time:
set time_now [clock seconds]
# Set the seconds to go back from the previously captured script start time:
set seconds_to_go_back [expr $time_now - $_s2FailDetect_second_diff]

# Timestamp the script start time to the output log file:
set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
puts $FH "*Timestamp = $date"

# Log the nodes hostname to the output log file:
set node [info hostname]
puts $FH "Node: $node"

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message the finally kicked off the EEM script:
set syslog_msg $arr_einfo(msg)

puts $FH "\n"
puts $FH "Final Syslog Trigger:"
puts $FH $syslog_msg
puts $FH "\n"

# Extract the first location from the triggering syslog event:
lappend locations [extract_location $syslog_msg]

# Capture the syslogs history:
set hist_list [sys_reqinfo_syslog_history]

# Remove the {} characters:
regsub -all {\{|\}} $hist_list {} hist_list
# Remove the " characters:
regsub -all {\"} $hist_list {} hist_list

foreach rec $hist_list {
  foreach syslog $rec {
    # Verify the syslog msg has the pattern we are searching on:
    if {[regexp "$pattern" $syslog]} {
      # Trim up the line remove extra space/tabs etc:
      regsub -all {[ \r\t\n]+} $syslog " " syslog
      # Remove any leading white space:
      regsub -all {^[ ]} $syslog "" syslog
      # Remove any ending white space:
      regsub -all {[ ]$} $syslog "" syslog

      if {[regexp {^time_sec} $syslog]} {
        # Extract the syslog msg time of occurrence:
        regexp {^time_sec (\d+) .*} $syslog - time_rec
        # If the syslog message time of occurrence is within our go_back time
        # then process the syslog msg:
        if {$time_rec > $seconds_to_go_back} {
          lappend locations [extract_location $syslog]
          puts $FH $syslog
        }
      }
    }
  }
}

puts $FH ""
puts $FH "locations before sort: $locations"
set unique_locations [lsort -unique $locations]
puts $FH "unique_locations: $unique_locations"
set num_unique_locations [llength $unique_locations]

if {$num_unique_locations > $_s2FailDetect_unique_locations} {
  # Proceed with the node COST OUT
  puts $FH "Unique Locations ($num_unique_locations) above configured _s2FailDetect_unique_locations: $_s2FailDetect_unique_locations"
  puts $FH "Continuing on with Costing Out node!"

  # Open Node Connection
  if [catch {cli_open} result] {
    error $result $errorInfo
  } else {
    array set cli $result
  }
  # Enter config terminal:
  if [catch {cli_exec $cli(fd) "config t"} result] {
    error $result $errorInfo
  }
  if [catch {cli_exec $cli(fd) "router ospf $_s2FailDetect_ospf_id"} result] {
    error $result $errorInfo
  }
  if [catch {cli_exec $cli(fd) "max-metric router-lsa include-stub"} result] {
    error $result $errorInfo
  }
  if [catch {cli_exec $cli(fd) "commit"} result] {
    error $result $errorInfo
  }
  if [catch {cli_exec $cli(fd) "end"} result] {
    error $result $errorInfo
  }
  # End of Configuration tasks

  # Send syslog message:
  action_syslog msg "EEM policy detected a possible Node S2 problem, COSTING OUT the node"
} else {
  # No COST OUT
  puts $FH "Unique Locations ($num_unique_locations) below threshold: $_s2FailDetect_unique_locations"
  puts $FH "Exiting EEM policy without Costing Out node"

  # Send syslog message:
  action_syslog msg "EEM policy detected a possible Node S2 problem, yet unique locations ($num_unique_locations) below threshold: $_s2FailDetect_unique_locations"
}

close $FH
