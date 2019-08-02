::cisco::eem::event_register_timer watchdog name timer100 sec 3600 maxrun 300

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

global term_rows
 
#
# proc xmit{} - procedure to execute a CLI command
#
proc xmit {cmd} {
  global errorInfo
  global term_rows
  upvar cli cli
 
  if [catch {cli_exec $cli(fd) "$cmd"} result] {
    error $result $errorInfo
  } else {
    set term_rows $result
  }
}
 
set errorInfo ""
set term_rows ""
 
set timestamp [clock format [clock seconds] -format "%Y-%m-%d_%H%M%S"]
 
set filename "harddisk:/anuara/sh-running-config-dedsdf1104jl1_$timestamp.txt"
 
# Open router connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}
 
xmit "ter le 0"
xmit "show run | file $filename"
after 10000


#xmit "scp $filename anuara@192.168.51.62:/home/anuara/"
set SCP "scp $filename anuara@192.168.51.62:/home/anuara/"
set password "Sp0rt!!"


# Enter the SCP command
if [catch {cli_write $cli(fd) "$SCP"} result] {
  error $result $errorInfo
}

# Waitfor the Password prompt
if [catch {cli_read_pattern $cli(fd) "assword:"} result] {
  error $result $errorInfo
}

# Send the password
if [catch {cli_write $cli(fd) "$password"} result] {
  error $result $errorInfo
}

xmit "end"


