#!/bin/sh
### TCE TESTCASE
### title: A failing command in a ttasim script makes ttasim exit 1, without waiting at the prompt
### xstdout: good script: 0\nfailing script: 1\nmissing machine: 1\nfailing script, interactive mode off: 1

mach=data/guard_latencies.adf
prog=data/guard_latencies.tpef

# stdin is a terminal-less empty stream: a ttasim waiting at its prompt would
# read EOF and quit with 0, so the exit codes below are what is checked.
ttasim -a $mach -p $prog -e "stepi 100; quit" > /dev/null 2>&1 < /dev/null
echo "good script: $?"

ttasim -a $mach -p $prog -e "stepi 100; puts [x /u w no_such_symbol]; quit" > /dev/null 2>&1 < /dev/null
echo "failing script: $?"

ttasim -a no_such_machine.adf -p $prog -e "run; quit" > /dev/null 2>&1 < /dev/null
echo "missing machine: $?"

ttasim --no-debugmode -a $mach -p $prog -e "puts [x /u w no_such_symbol]" > /dev/null 2>&1 < /dev/null
echo "failing script, interactive mode off: $?"
