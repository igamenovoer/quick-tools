#! /bin/bash

# by default, ntp may not be working correctly.
# force time sync with ntpdate

sudo apt install ntpdate
sudo ntpdate pool.ntp.org
