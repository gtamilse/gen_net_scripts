::cisco::eem::event_register_syslog pattern "SSHD_.*SECURITY-SSHD-3-ERR_GENERAL.*Failed to allocate pty" maxrun 180

#------------------------------------------------------------------
# Enable 'debug ssh server' if the above syslog pattern is detected
#
# May 2013 - Scott Search (ssearch@cisco.com)
#
# This EEM script is triggered off the following syslog event:
#
# Feb 26 06:17:21.455 : SSHD_[65849]: %SECURITY-SSHD-3-ERR_GENERAL : Failed to allocate pty
#
# Once triggered the script will login to the router enter configuration mode and enable 'logging buffered debug'
# The script will commit this for a 60 second timeout then the XR SW will automatically back-out the configuration
# change.  During this 60 second period the script will enable 'debug ssh server'  After the 60 second backup
# time is up the script will perform a 'show log | inc SSHD | inc "<month> <day"' and save this data to the 
# script logging location set via the event manager environment variable to a file debug_ssh_server_<time>_<date>
#
# Copyright (c) 2013 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
#
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

# Verify the environment vars:
if {![info exists _debug_ssh_server_storage_location]} {
  set result "EEM policy error: environment var _debug_ssh_server_storage_location not set"
  error $result $errInfo
}

###########################################
# Procs
###########################################
proc sleep {wait_time} {
  after [expr {int($wait_time * 1000)}]
}

###########################################
# Main/main
###########################################
# Globals
global FH
global _debug_ssh_server_storage_location

set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
set stamp [clock format [clock sec] -format "%T_%b_%d_%Y"]
set month_day [clock format [clock sec] -format "%b %d"]
regsub -all {:} $stamp "." stamp
set _output_log "debug_ssh_server_$stamp"

# set the array arr_einfo to the eem event_reqinfo
array set arr_einfo [event_reqinfo]
# extract the syslog message:
set syslog_msg $arr_einfo(msg)

# open the output file (for write):
if [catch {open $_debug_ssh_server_storage_location/$_output_log w} result] {
    error $result
}
set FH $result

puts $FH "*Timestamp = $date"
puts $FH "Cisco Debug SSH Server\n"

puts $FH "SYSLOG MSG:\n$syslog_msg\n\n"

# Open Node Connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

# Set node hostname:
set node [info hostname]
puts $FH "Node: $node"

if [catch {cli_exec $cli(fd) "config"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "logging buff debug"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "commit confirm 60"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "do debug ssh server"} result] {
  error $result $errorInfo
}

# sleep for 62 seconds.  Then exit from config mode.
sleep 62

if [catch {cli_exec $cli(fd) "end"} result] {
  error $result $errorInfo
}
if [catch {cli_exec $cli(fd) "undebug all"} result] {
  error $result $errorInfo
}

# Next do a 'show log | inc SSHD | inc "<month> <day>"'
if [catch {cli_exec $cli(fd) "show log | inc SSHD | inc \"$month_day\""} result] {
  error $result $errorInfo
}
set retval $result
puts $FH "SSH Server Debugs:\n$retval"
close $FH

if [catch {cli_close $cli(fd) $cli(tty_id)} result] {
    error $result $errorInfo
}

set msg "Completed the EEM policy debug_ssh_server"
action_syslog msg $msg
