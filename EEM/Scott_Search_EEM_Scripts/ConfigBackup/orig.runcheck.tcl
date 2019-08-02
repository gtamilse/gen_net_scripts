#::cisco::eem::event_register_timer cron name teamops cron_entry "* /2 * * * *" maxrun_sec 240
::cisco::eem::event_register_timer watchdog name timer100 sec 7200 maxrun 300

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
 
set saveFile "file harddisk:/anuara/sh-running-config-dedsdf1104jl1_$timestamp.txt"
 
xmit "ter le 0"
xmit "show run | $saveFile"
xmit "scp $file_name anuara@192.168.51.62:/home/anuara/"
after 5000
xmit "Sp0rt!!"
uara/"
after 5000
xmit "Sp0rt!!"
"
