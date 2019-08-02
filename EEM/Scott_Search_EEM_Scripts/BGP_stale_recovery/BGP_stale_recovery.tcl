:cisco::eem::event_register_syslog occurs 30 period 60 pattern "ROUTING-BGP-3-NBR_NSR_DISABLED : NSR disabled on neighbor.*due to TCP retransmissions" maxrun 300

#------------------------------------------------------------------
# To verify we are hitting a problem do the following comparison:
#
# show bgp sum                                
# show bgp vrf all sum |  utility egrep ^[1-9]  
# show bgp vpnv4 unicast summary | util egrep ^[1-9]
#
#
# Compare the above output to the standby commands below:
#
# show bgp summary standby | util egrep ^[1-9] 
# show bgp vrf all summary standby | util egrep ^[1-9]      
# show bgp vpnv4 unicast summary standby | util egrep ^[1-9]
#
# If the Standby shows the BGP peers down then we need to do the workaround by shutting down that peer for 1 minute
#
#------------------------------------------------------------------
#
# BGP_stale_recovery EEM Script
#
# October 2013 - Scott Search (ssearch@cisco.com)
#
# This EEM script will be triggered off a high number of BGP NSR disabled messages.  The script is
# intended to recover from the BGP stale routes:
#
# CSCuh02932    BGP Stale routes seen when a peer runs into TCP Oper-Down back-2-back 
# AT&T Cisco SR: 632032259
#
#
# EEM Script is dependent on the following event manager environment variables:
#   _BGP_stale_recovery_storage_location <storage>  -Disk/hardisk storage location "harddisk:/eem"
#
# Email Option
# To activate the email option the following event manager environment variables must be set:
#   _email_server    _email_from
#   _email_to        _domainname
#
#
# EEM Script Logic:
#
# The script is triggered by the syslog pattern above.  If the pattern occurs 30 times and within
# a 60 second period this EEM policy will be started.  The script checks the syslogs via the
# sys_reqinfo_syslog_history for matching events within the 60 second period.  From the syslog
# pattern match if the same BGP peer reported the BGP NSR disabled more than 30 times in a 60 second
# period this EEM script will continue and proceed with the workaround for CSCuh02932.  
#
# Copyright (c) 2014 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
#
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
##########################################################################################
# Set the pattern the script will filter on (maybe set within the eem environment vars):
##########################################################################################
set pattern "ROUTING-BGP-3-NBR_NSR_DISABLED : NSR disabled on neighbor"

##################################
# Verify the environment vars:
##################################
# Storage location:
if {![info exists _BGP_stale_recovery_storage_location]} {
  set result "EEM policy error: environment var _BGP_stale_recovery_storage_location not set"
  error $result $errInfo
}

# Below var flag is used to verify if the BGP_stale_recovery.tcl script has run previously:
set run_flag "$_BGP_stale_recovery_storage_location/run_flag"

##################################
# PROCs:
##################################
proc extract_location {line} {
  global FH
  set location ""

  regsub -all {[ \r\t\n]+} $line " " line
  regsub -all {^[ ]} $line "" line
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
} ;# extract_location

proc GetDups {list} {
  array set tmp {}

  # Count the elements in the list
  foreach item $list {
    lappend tmp($item) .
  }

  foreach item [array names tmp] {
    ;# We will unset any element with a count that is not greater or equal to 5 
    if {[llength $tmp($item)] >= 5} continue
    unset tmp($item)
  }

  # Return the array
  return [array names tmp]
} ;# GetDups


proc get_bgp_peers {syslogs} {
  set peers ""
  set peer ""

  foreach line [split $syslogs "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp "ROUTING-BGP-3-NBR_NSR_DISABLED : NSR disabled on neighbor" $line]} {
      regexp { neighbor (\d+\.\d+\.\d+\.\d+)} $line - peer
      lappend peers $peer
    }
  }
  return $peers
} ;# get_bgp_peers


proc send_syslog {msg repeat} {
  set kont 0

  while {$kont < $repeat} {
    action_syslog msg $msg
    incr kont
  }
} ;# send_syslog

proc send_email {node syslog_msg msg} {
  global FH
  global _email_to _email_from
  global _email_server _domainname
  global email_subject

  action_syslog msg "Sending BGP_stale_recovery run notification to $_email_to"

  foreach recipient [split $_email_to " "] {
    set email [format "Mailservername: %s" "$_email_server"]
    set email [format "%s\nFrom: %s" "$email" "$_email_from"]
    set email [format "%s\nTo: %s" "$email" "$recipient"]
    set email [format "%s\nCc: %s" "$email" ""]
    set email [format "%s\nSubject: %s\n" "$email" $email_subject]

    # Email BODY:
    set email [format "%s\n%s" "$email" "The $node node run the BGP_stale_recovery EEM script for syslog:"]
    set email [format "%s\n%s\n\n" "$email" "$syslog_msg"]
    set email [format "%s\n%s" "$email" "$msg"]
   
    # Send email message:
    if [catch {smtp_send_email $email} result] {
      puts "smtp_send_email: $result"
    }
 
    puts $FH "EMAIL DATA BELOW SENT TO: $_email_to\n"
    puts $FH $email
  }
} ;# send_email


##################################
# MAIN/main
##################################
global FH
global _email_to _email_from
global _email_server _domainname
global email_subject

set locations ""
set bgp_peers ""

# Capture the scripts start time:
set time_now [clock seconds]

set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

set filename "BGP_stale_recovery.$date_time"
set output_file "$_BGP_stale_recovery_storage_location/$filename"

# Open the output file (for write):
if [catch {open $output_file w} result] {
    error $result
}
set FH $result

# Timestamp the script start time to the output log file:
puts $FH "Start Timestamp: $date"

# Log the nodes hostname to the output log file:
set node [info hostname]
set email_subject "**Node $node Possible BGP stale route Detection**"
puts $FH "Node: $node"

# Set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# Extract the syslog message the finally kicked off the EEM script:
set syslog_msg $arr_einfo(msg)


# If the $run_flag file exists exit from script:
if [file exists $run_flag] {
  set msg "EEM policy BGP_stale_recovery.tcl detected possible BGP stale state, yet $run_flag exists No Action Taken!"
  action_syslog msg $msg

  set msg "$msg\nDelete $run_flag in order to activate the EEM BGP_stale_recovery.tcl script."
  set msg "$msg\n\nThe $node node experienced the following syslog:"
  set msg "$msg\n$syslog_msg"
  puts $FH $msg
  close $FH
  exit
}

# Create the $fab_detect_run_flag file
if [catch {open $run_flag w} result] {
    error $result
}
set RUN $result
puts $RUN "Timestamp = $date"
close $RUN


# Go back in the routers log 3 minutes to determine the BGP peers in the NSR disabled state
set go_back_3min [expr $time_now - 180]
# Create the 'show log' command to run on the router
set show_log_DateTime [clock format $go_back_3min -format "%b %d %H:%M:%S"]
set show_log_start_CMD "show log start $show_log_DateTime | inc ROUTING-BGP-3-NBR_NSR_DISABLED : NSR disabled on"

puts $FH "\n"
puts $FH "Final Syslog Trigger:"
puts $FH $syslog_msg
puts $FH "\n"
puts $FH "EEM script will run following CMD below to get the recent history (last 3 minutes) of syslogs:\n"
puts $FH "CMD: $show_log_start_CMD\n"
puts $FH "\n"

puts $FH "Opening router connection\n"

# Open router connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

set cmd $show_log_start_CMD
puts $FH "Running CMD: $cmd\n"
if [catch {cli_exec $cli(fd) $cmd} result] {
  error $result $errorInfo
}
puts $FH "$result\n\n"

# Extract the BGP peers
set bgp_peers [get_bgp_peers $result]

# Call on the GetDups proc to only hold onto BGP peers that were seen 5 times or more
set bgp_peers [GetDups $bgp_peers]






if [catch {cli_exec $cli(fd) "commit"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "end"} result] {
  error $result $errorInfo
}
# End of CARD shutdown tasks



# ssearch

# config
# router bgp 13979
# neighbor 192.168.0.2 shut
# commit
# end
# !
# config      
# router bgp 13979         
# no neighbor 192.168.0.2 shut
# commit
# end








close $FH
