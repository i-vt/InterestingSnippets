#!/bin/bash
# normal.sh — Generate normally distributed random numbers using AWK
# Usage: ./normal.sh <mean> <stddev> <count>

mean=${1:-0}       # default mean
stddev=${2:-1}     # default standard deviation
count=${3:-10}     # default number of samples

awk -v mean="$mean" -v stddev="$stddev" -v count="$count" '
BEGIN {
    srand();   # seed from current time
    for (i = 0; i < count; i++) {
        # Box–Muller: two uniform(0,1)
        u1 = rand();
        u2 = rand();
        z = sqrt(-2 * log(u1)) * cos(2 * 3.141592653589793 * u2);
        x = mean + stddev * z;
        print x;
    }
}
'
