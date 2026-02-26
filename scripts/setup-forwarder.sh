#!/bin/bash
# Splunk Universal Forwarder — Target Pi (ARM64)
# Forwards auth.log and syslog to the Splunk indexer at 192.168.30.10:9997
# Run this on the target Pi while it still has internet access,
# then move it into the range.

SPLUNK_IP="192.168.30.10"
SPLUNK_PORT="9997"

# Download and install the ARM64 forwarder package
wget -O /tmp/splunkforwarder.deb \
  "https://download.splunk.com/products/universalforwarder/releases/9.2.1/linux/splunkforwarder-9.2.1-78803f08aabb-linux-aarch64.deb"

sudo dpkg -i /tmp/splunkforwarder.deb

# Confirm install
dpkg -l | grep splunk

# Start and accept license
sudo /opt/splunkforwarder/bin/splunk start --accept-license

# Point forwarder at the Splunk indexer
sudo /opt/splunkforwarder/bin/splunk add forward-server ${SPLUNK_IP}:${SPLUNK_PORT}

# Add log sources to monitor
sudo /opt/splunkforwarder/bin/splunk add monitor /var/log/auth.log
sudo /opt/splunkforwarder/bin/splunk add monitor /var/log/syslog

echo ""
echo "Verifying connectivity to Splunk indexer..."
nc -zv ${SPLUNK_IP} ${SPLUNK_PORT}
# Expected: "Connection to 192.168.30.10 9997 port [tcp/*] succeeded!"
