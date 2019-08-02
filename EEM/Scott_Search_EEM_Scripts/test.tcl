::cisco::eem::event_register_timer cron name test cron_entry "0,5,10,15,20,25,30,35,40,45,50,55 * * * *" maxrun_sec 60

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

if [catch {cli_exec $cli(fd) "show version brief"} result] {
  error $result $errorInfo
}

cli_close $cli(fd) $cli(tty_id)

