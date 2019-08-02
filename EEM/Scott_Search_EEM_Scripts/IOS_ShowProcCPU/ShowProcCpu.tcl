::cisco::eem::event_register_timer cron name ShowProcCpu cron_entry "0,30 * * * *" maxrun_sec 120

#------------------------------------------------------------------
# ShowProcCpu.tcl
#
# 10/27/11 - Scott Search (ssearch@cisco.com)
#
# event manager environment variable:
#   _ShowProcCpu_file <storage>    -Example:  event manager environment _ShowProcCpu_file disk2:/eem/test
#
#
# This EEM script runs every 30 minutes and captures the 'show proc cpu' from the router. Then saves
# the output to the file $_ShowProcCpu_file
#
# Copyright (c) 2011 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

if {![info exists _ShowProcCpu_file]} {
  set result "EEM Policy cannot be run, environmentvariable _ShowProcCpu has not been set"
  error $result $errorInfo
}

if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

if [catch {cli_exec $cli(fd) "term len 0"} result] {
        error $result $errorInfo
}

set time_now [clock seconds]
set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]

if [catch {cli_exec $cli(fd) "show proc cpu"} result] {
        error $result $errorInfo
} 
set ShowProcCPU $result

if [catch {open $_ShowProcCpu_file a} result] {
  error $result
}
set FH $result
puts $FH "*Timestamp = $date_time"

puts $FH "$ShowProcCPU\n\n\n"

close $FH
