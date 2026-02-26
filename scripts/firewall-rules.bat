# Optiplex (Windows 10) — Splunk Indexer Firewall Rules
# Run these in an elevated Command Prompt or PowerShell on the Optiplex.
# Required to allow ICMP pings from the range and Splunk forwarder traffic on 9997.

# Allow inbound ICMP (so Pis can ping the Optiplex to verify connectivity)
netsh advfirewall firewall add rule name="Allow ICMP" protocol=icmpv4 dir=in action=allow

# Allow inbound TCP 9997 (Splunk forwarder port)
netsh advfirewall firewall add rule name="Splunk Forwarder" dir=in action=allow protocol=TCP localport=9997

# Verify Splunk is listening on 9997 after enabling the receiving port in Splunk UI
# Settings > Forwarding and Receiving > Configure Receiving > New > Port 9997
netstat -an | findstr 9997
# Expected output includes: TCP    0.0.0.0:9997    ...    LISTENING
