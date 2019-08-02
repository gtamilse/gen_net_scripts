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
xmit "scp $filename anuara@192.168.51.62:/home/anuara/"






#xmit "scp /harddisk:/eem/TEST anuara@192.168.51.62:/home/anuara/"
#xmit "copy /harddisk:/eem/cfgbkup.tcl ftp://anuara:Sp0rt!!@192.168.51.62"
screenSave $term_rows
after 12000
xmit "Sp0rt!!"
#screenSave $term_rows
xmit "end"


