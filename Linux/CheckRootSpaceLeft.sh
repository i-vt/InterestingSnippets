#!/bin/bash

available=$(df -h / | awk 'NR==2 {print $4}')
echo "/:$available"
