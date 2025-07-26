#!/bin/bash

echo "Local Time:       $(date)"
echo "UTC:              $(TZ=UTC date)"
echo "Moscow:           $(TZ=Europe/Moscow date)"
echo "India (Delhi):    $(TZ=Asia/Kolkata date)"
echo "Poland:           $(TZ=Europe/Warsaw date)"
echo "Nigeria:          $(TZ=Africa/Lagos date)"
