#!/bin/bash
# Installs Splunk inside a plain Ubuntu 22.04 AMD64 container.
#
# The official splunk/splunk image uses an Ansible-based entrypoint that breaks
# under QEMU userspace emulation on ARM64 — specifically, QEMU doesn't properly
# emulate setuid binaries like sudo, causing the entrypoint to fail regardless
# of ANSIBLE_BECOME settings. Skipping the official image entirely sidesteps
# the problem: a plain Ubuntu container has no entrypoint, no Ansible, and no
# privilege escalation needed since we run as root directly.
#I decided to leave this in the repo because it's useful if anyone else wants to
#try this, but I had already decided to run with the Optiplex instead. 

docker rm -f splunk 2>/dev/null

docker run -d \
  --name splunk \
  --platform linux/amd64 \
  --privileged \
  -p 8000:8000 \
  -p 9997:9997 \
  ubuntu:22.04 \
  sleep infinity

echo "Container started. Running Splunk install..."

docker exec splunk bash -c "
  apt-get update && apt-get install -y wget libgssapi-krb5-2 && \
  wget -O /tmp/splunk.deb 'https://download.splunk.com/products/splunk/releases/9.2.1/linux/splunk-9.2.1-78803f08aabb-linux-2.6-amd64.deb' && \
  dpkg -i /tmp/splunk.deb && \
  /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --run-as-root
"

echo "Splunk should be available at http://192.168.30.50:8000"
