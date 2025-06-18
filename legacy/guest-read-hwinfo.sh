#!/bin/bash
#

sudo strings /sys/firmware/acpi/tables/SSDT* 2>/dev/null | grep -A 1 -B 1 "NVME_SERIAL\|MAC_ADDRESS"

