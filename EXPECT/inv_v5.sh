#!/bin/bash

# Used with the cbbcmds script

nlines=`cat $1 | wc -l`
nthread=$((nlines/9))
echo $nthread "nodes per thread \n"
for ((i=0; i<=7; i++))
do
sed -n "$(((i*nthread)+1))","$(((i+1)*nthread))"p $1  > US_"$((i+1))"0.nds
done
sed -n "$((8*nthread+1))","$nlines"p $1 > US_90.nds

for ((i=0; i<=8; i++))
do
./cbbruncmd_console_multi_v33.exp US_"$((i+1))"0.nds $2 $3 > US_"$((i+1))"0.inv & # Fork all the scripts
done

wait %1
wait %2
wait %3
wait %4
wait %5
wait %6
wait %7
wait %8
wait %9


exit 0
