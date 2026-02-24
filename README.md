# Home Cyber Range

A physical, multi-VLAN cyber range built on Raspberry Pis and real Cisco hardware. Designed for practicing offensive security, defensive monitoring, and network engineering in a realistically segmented environment.

---

## Hardware

| Component | Device |
|-----------|--------|
| Attacker | Raspberry Pi 5 — Kali Linux |
| Target | Raspberry Pi 3 Model A+ — Ubuntu 20.04.5 LTS |
| Defender/SIEM | Raspberry Pi 5 (8GB) — Splunk Enterprise via Docker |
| Router | Cisco 2621 |
| Switch | Cisco Catalyst 2950 |
| AP | Linksys E5350 (flashed with OpenWRT) |

---

## Network Design

### IP Scheme

| Role | VLAN | Subnet | Device IP | Gateway |
|------|------|--------|-----------|---------|
| Attacker | 10 | 192.168.10.0/24 | 192.168.10.50 | 192.168.10.1 |
| Target | 20 | 192.168.20.0/24 | 192.168.20.50 | 192.168.20.1 |
| Splunk/SIEM | 30 | 192.168.30.0/24 | 192.168.30.50 | 192.168.30.1 |

Splunk gets its own VLAN for enterprise realism — in a real SOC, the monitoring infrastructure is always isolated from the networks it watches.

### Physical Wiring

```
[RPi 5 Kali]
     |
     Fa0/0
     |
[Cisco 2621 Router]
     |
     Fa0/1 (trunk)
     |
     Fa0/24 (trunk)
     |
[Cisco Catalyst 2950 Switch]
     |              |
  Fa0/1-4        Fa0/5-8
  (VLAN 20)      (VLAN 30)
     |              |
[RPi 3A+ Target] [RPi Splunk]
```

### Router-on-a-Stick

The Cisco 2621 only has one interface facing the switch, so inter-VLAN routing is done via subinterfaces on Fa0/1. Each subinterface gets `encapsulation dot1Q <vlan-id>`, which tags outgoing frames so the switch knows which VLAN they belong to. The switch port on the other end is configured as a trunk so it accepts these tagged frames rather than dropping them.

---

## Router Setup

**Hardware:** Cisco 2621  
**Console:** COM3, baud 9600 (via PuTTY)  
**Config file:** [`router/config.ios`](router/config.ios)

### Password Recovery

If the enable password is unknown, break into ROMMON mode:

1. In PuTTY: **right-click the title bar → Send Command → Break** while the router is booting
2. At the `rommon>` prompt, tell the router to ignore its startup config:
   ```
   confreg 0x2142
   reset
   ```
3. At the setup dialogue, answer **no**
4. Enter enable mode (no password required now), then reset cleanly:
   ```
   enable
   erase startup-config
   reload
   ```
5. Reconfigure from scratch using [`router/config.ios`](router/config.ios)

### Key config notes

- `no ip domain-lookup` — stops the router trying to DNS-resolve mistyped commands, which would cause a long hang
- `ip routing` — enables L3 routing between interfaces (off by default on some IOS versions)
- The parent interface `Fa0/1` has **no IP address** — IPs live on the subinterfaces only. Trunks don't need IPs; they're just links.
- `encapsulation dot1Q` implements 802.1Q frame tagging, which is what makes router-on-a-stick work

---

## Switch Setup

**Hardware:** Cisco Catalyst 2950  
**Config file:** [`switch/config.ios`](switch/config.ios)

### Key config notes

- Management IP is on VLAN 1 (`192.168.20.2`), with the default gateway pointing at the router
- `no ip domain-lookup` — same reason as the router
- The trunk port `Fa0/24` uses `switchport trunk allowed vlan 10,20,30,1002-1005` — the `1002-1005` are legacy reserved VLANs that Cisco requires be present in the allowed list, otherwise the command is rejected with `Bad VLAN list`. These date back to when Cisco switches supported non-Ethernet L2 technologies (FDDI, Token Ring) and needed those VLANs to trunk alongside Ethernet VLANs.
- Without a trunk port, tagged frames from the router's subinterfaces would be dropped — access ports only accept untagged frames for a single VLAN

### Verify after applying config

```
show vlan brief
show interfaces status
show running-config
```

---

## Attacker Setup (RPi 5 — Kali)

1. Flash Kali Linux ARM64 image to SD card using Raspberry Pi Imager
   - Hostname: `attacker`, username: `offsec`
2. Set static IP by editing `/etc/network/interfaces`:
   ```
   auto eth0
   iface eth0 inet static
     address 192.168.10.50
     netmask 255.255.255.0
     gateway 192.168.10.1
   ```
3. Apply: `sudo systemctl restart networking`

See [`attacker/`](attacker/) for future tooling and scripts.

---

## Target Setup (RPi 3 Model A+ — Ubuntu 20.04)

**Netplan config:** [`target/netplan.yaml`](target/netplan.yaml)

Ubuntu 20.04 manages networking via **Netplan** (YAML-based), not `/etc/network/interfaces`. The legacy `ifconfig` and `route` commands are also not installed by default — use `ip a` and `ip route` instead.

Copy [`target/netplan.yaml`](target/netplan.yaml) to `/etc/netplan/01-netcfg.yaml` and apply:
```bash
sudo netplan apply
```

### Password Recovery (Ubuntu on RPi)

The typical `init=/bin/bash` kernel parameter causes a **kernel panic** on this setup. The reason: `init=/bin/bash` is interpreted during the initramfs stage, before the real root filesystem is mounted — and initramfs doesn't have bash, so the kernel panics trying to find it.

The fix is to let initramfs complete normally, then intercept at the systemd level:

1. Mount the SD card on another machine and open `cmdline.txt`
2. Append `systemd.unit=emergency.target` to the existing line (do not add a new line — `cmdline.txt` must be a single line)
3. Boot the Pi — it will drop into a root emergency shell
4. Remount the root filesystem as read-write and change the password:
   ```bash
   mount -o remount,rw /
   passwd root
   sync
   ```
5. Shut down, remove `systemd.unit=emergency.target` from `cmdline.txt`, and boot normally

---

## Splunk Setup (RPi 5 — Docker + QEMU)

**Scripts:** [`splunk/docker-run.sh`](splunk/docker-run.sh), [`splunk/binfmt-qemu-x86_64.service`](splunk/binfmt-qemu-x86_64.service)

Splunk Enterprise only publishes AMD64 images — no ARM64 support. On the RPi, we work around this with Docker + QEMU user-mode emulation, which lets the ARM64 host run AMD64 containers.

### 1. Install dependencies

```bash
sudo apt install -y docker.io qemu-user-static binfmt-support
```

- `qemu-user-static` — provides the QEMU binary that translates AMD64 instructions to ARM64 at runtime
- `binfmt-support` — tells the Linux kernel to invoke QEMU automatically when it encounters an AMD64 ELF binary
- `docker.io` — runs the containers

```bash
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker   # activates group membership without logging out
```

### 2. Register the QEMU binfmt handler

The `binfmt-support` package sometimes doesn't register the handler automatically. If `docker run --platform linux/amd64` fails with an exec format error, register it manually:

```bash
printf ':qemu-x86_64:M:0:\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-x86_64-static:F\n' \
  | sudo tee /proc/sys/fs/binfmt_misc/register
```

This write to `/proc` doesn't survive a reboot. To make it persistent, install the systemd service:

```bash
sudo cp splunk/binfmt-qemu-x86_64.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable binfmt-qemu-x86_64.service
sudo systemctl start binfmt-qemu-x86_64.service
```

Verify registration:
```bash
cat /proc/sys/fs/binfmt_misc/qemu-x86_64
```

Test with a lightweight AMD64 container before pulling the full Splunk image:
```bash
docker run --platform linux/amd64 --rm alpine uname -m
# should output: x86_64
```

### 3. Run Splunk

```bash
bash splunk/docker-run.sh
docker logs -f splunk   # watch startup, takes a few minutes
```

Splunk UI will be available at `http://192.168.30.50:8000`  
Default login: `admin` / `CyberRangeP4ssword!`

**Note on `--privileged`:** The Docker run command uses `--privileged`, which gives the container full access to host capabilities and removes `nosuid` restrictions. This is required for QEMU-based AMD64 emulation on ARM. It's a security concern in production but acceptable in an isolated lab.

**Note on performance:** Splunk running under QEMU emulation on an RPi will be slow under load. If performance becomes an issue:
- Run Splunk off an SSD instead of the microSD card
- Reduce indexing threads and search concurrency in `limits.conf`
- Switch to RPi OS Lite (no desktop environment) to free up RAM
- Move Splunk to a more capable x86 machine (e.g., an old Optiplex)

---

## Connectivity Verification

Once everything is up, verify from the attacker Pi:

```bash
ping 192.168.10.1   # local gateway (router Fa0/0)
ping 192.168.20.1   # router subinterface for VLAN 20
ping 192.168.20.50  # target
ping 192.168.30.50  # splunk
```

---

## Troubleshooting

**Router config not saving after reboot**  
Always run `write memory` (or `copy running-config startup-config`) before disconnecting the console cable. If the hostname reverts, the config wasn't saved.

**`Bad VLAN list` error on switch trunk port**  
The trunk allowed list must include VLANs 1002–1005. Use `switchport trunk allowed vlan 10,20,30,1002-1005` rather than trying to add VLANs incrementally.

**VLAN 10 traffic not reaching targets through switch**  
The trunk port allowed list defaults to VLAN 1 only. Explicitly add all VLANs: `switchport trunk allowed vlan 10,20,30,1002-1005`.

**`encapsulation dot1Q` overlap error on router**  
If you see `% overlaps with FastEthernet0/1`, the parent interface still has an IP address. Remove it with `no ip address` on `Fa0/1` before configuring subinterfaces.

**`init=/bin/bash` causes kernel panic on Ubuntu RPi**  
See the password recovery section under Target Setup above. Use `systemd.unit=emergency.target` instead.

**QEMU binfmt handler not registered after reboot**  
Install and enable `splunk/binfmt-qemu-x86_64.service` — see Splunk Setup step 2.

**Splunk container exits immediately**  
Remove the old container first (`docker rm splunk`) before re-running `docker-run.sh`. Also ensure both volume directories exist (`~/splunk/etc` and `~/splunk/data`).
