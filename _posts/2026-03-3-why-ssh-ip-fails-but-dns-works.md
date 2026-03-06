---
layout: post
title: Why SSH IP failed, but Public DNS worked ??
categories: [Technical]
tags: [AWS, Networking]
# banner_image: /public/assets/chipwar.png
---


# Why SSH via IP Failed but Public DNS Worked — A Deep Dive into NAT64, IPv6, and Modern ISP Networks

> **TL;DR** — If you're in India (Jio/Airtel) and can SSH into your EC2 instance using a hostname but not a raw IP address, your ISP has deployed an IPv6-only network with NAT64 translation. This isn't a bug — it's the future of networking, and understanding it makes you a better cloud engineer.

---

## The Setup

I was building an AWS cross-region migration lab — spinning up a VPC, subnets, security groups, and an EC2 instance in `us-east-1` as the source environment to migrate to `eu-west-1`.

Everything was configured correctly:
- VPC with public subnet and Internet Gateway ✅
- Security group allowing port 22 from my IP ✅
- EC2 instance running with a public IP ✅
- Key pair created and saved locally ✅

Then I tried to SSH in.

---

## The Symptom

```bash
# Using raw IPv4 — FAILS
ssh -i ~/.ssh/migration-lab-key.pem ec2-user@98.80.179.31
# ssh: connect to host 98.80.179.31 port 22: No route to host

# Using public DNS hostname — WORKS
ssh -i ~/.ssh/migration-lab-key.pem ec2-user@ec2-98-80-179-31.compute-1.amazonaws.com
# Connected! Amazon Linux 2023 banner appears
```

Same EC2 instance. Same port. Same key. One works, one doesn't.

My first instinct was to blame the security group, the route table, or the internet gateway. But all of those checked out perfectly. The networking inside AWS was flawless.

The problem wasn't in AWS at all.

---

## The Investigation

### Step 1 — Traceroute

```bash
traceroute 98.80.179.31
# 1  thinkpad (10.141.119.52)  3063ms  !H  !H  !H

traceroute ec2-98-80-179-31.compute-1.amazonaws.com
# 1  thinkpad (10.141.119.52)  3089ms  !H  !H  !H
```

Both hit the same first hop — my own machine's gateway. The `!H` flag means **"Host Unreachable"** — my router was actively rejecting the packet before it even left my network. And crucially, both routes behaved identically here, so the difference wasn't in routing.

### Step 2 — The curl reveal

```bash
curl -v http://98.80.179.31 2>&1
# Trying 98.80.179.31:80...
# No route to host ❌

curl -v http://ec2-98-80-179-31.compute-1.amazonaws.com 2>&1
# Host resolved.
# IPv6: 64:ff9b::6250:b31f   ← interesting...
# IPv4: 98.80.179.31
# Trying [64:ff9b::6250:b31f]:80...
# Connected! ✅
```

There it was. When using the hostname, curl resolved **two addresses** — an IPv4 and an IPv6. It tried IPv6 first and connected immediately. When using the raw IPv4, there was no IPv6 fallback. The connection died.

### Step 3 — Checking my actual network interfaces

```bash
ip addr show | grep -E "inet |inet6"

# inet  10.141.119.52/24        ← Private IPv4 (LAN only)
# inet6 2409:40f2:2004:35cf::.../64  ← Public IPv6 ✅
# inet6 fe80::fdc2:.../64            ← Link-local IPv6
```

No public IPv4 address anywhere on my machine. `10.141.119.52` is a private RFC1918 address — it only works inside my local network. My only real internet-routable address is the IPv6 one.

### Step 4 — Confirming IPv4 is dead

```bash
curl -4 https://checkip.amazonaws.com
# Failed to connect — timeout ❌

curl -6 https://checkip.amazonaws.com
# 157.50.171.149 ✅
```

IPv4 to the public internet: completely broken. IPv6: works perfectly.

---

## The Root Cause: NAT64 / DNS64

My ISP (Jio — identifiable by the `2409:40f2` IPv6 prefix) has deployed an **IPv6-only last mile** network. My device gets a real public IPv6 address but **no public IPv4 address**. Since most of the internet still runs on IPv4, the ISP bridges the gap using two technologies:

### DNS64
When you query a hostname, the ISP's DNS server checks if the destination has an IPv6 address. If it only has IPv4, DNS64 **synthesizes** a fake IPv6 address by embedding the IPv4 address inside the special `64:ff9b::/96` prefix.

```
EC2's real IPv4:    98.80.179.31
In hex:             62  50  b3  1f
Synthesized IPv6:   64:ff9b::6250:b31f
```

You can verify this yourself — the last 32 bits of `64:ff9b::6250:b31f` are exactly `98.80.179.31` in hexadecimal.

### NAT64
When your device sends a packet to a `64:ff9b::` address, the ISP's NAT64 gateway intercepts it, strips the IPv6 wrapper, and forwards it as a real IPv4 packet using the ISP's own public IPv4 address pool.

```
Your device sends:   IPv6 packet to 64:ff9b::6250:b31f
NAT64 gateway sees:  64:ff9b:: prefix → needs translation
NAT64 forwards:      IPv4 packet to 98.80.179.31
                     Source IP: 157.50.171.149 (ISP's exit IP)
```

That `157.50.171.149` — the IP that `checkip.amazonaws.com` returns — **is not your IP**. It's your ISP's NAT64 gateway, shared among potentially thousands of customers.

---

## The Full Picture

```
┌──────────────────────────────────────────────────────────────┐
│                       YOUR DEVICE                            │
│                                                              │
│   Private IPv4: 10.141.119.52  (LAN only, can't reach WAN)  │
│   Public  IPv6: 2409:40f2::... (real internet address)       │
└─────────────────────────┬────────────────────────────────────┘
                          │ IPv6 traffic only
                 ┌────────▼────────┐
                 │  Jio NAT64 GW   │
                 │ 157.50.171.149  │
                 │  IPv6 → IPv4    │
                 └────────┬────────┘
                          │ IPv4 traffic
                 ┌────────▼────────┐
                 │   AWS EC2       │
                 │  98.80.179.31   │
                 └─────────────────┘
```

**Why the raw IP fails:** When you type `98.80.179.31` directly, you bypass DNS entirely. DNS64 never runs. No IPv6 address gets synthesized. Your IPv6-only device has no path to an IPv4 destination — packet dropped.

**Why the hostname works:** DNS64 synthesizes `64:ff9b::6250:b31f`. Your device sends IPv6. NAT64 translates it to IPv4. EC2 receives it from `157.50.171.149`. Connection established.

---

## Why This Matters for Cloud Engineers

### 1. Security Group Rules Behave Differently Than Expected

When you run `curl https://checkip.amazonaws.com` to get "your IP" for a security group rule, you're actually getting your ISP's NAT64 exit IP — shared with thousands of other customers. If that IP rotates or changes, your rule breaks. This is why **AWS Systems Manager Session Manager (SSM)** is the enterprise-grade solution — it needs zero open inbound ports.

### 2. IPv6-Only Deployments Are the Present, Not the Future

IPv4 addresses officially ran out. APNIC (the Asia-Pacific registry) has been in exhaustion since 2011. ISPs in India, particularly Jio, are now deploying IPv6-only networks at scale. As a cloud engineer, understanding NAT64/DNS64 is no longer optional — you will encounter this.

### 3. Always Use DNS Hostnames, Not Raw IPs

This incident reinforces AWS best practices: always reference resources by DNS name, not IP. IPs change when instances restart. DNS names are stable. And as we've seen, DNS names work even when raw IPs don't, because DNS64 can bridge the gap.

### 4. "No Route to Host" Doesn't Always Mean AWS Misconfiguration

Before spending an hour checking route tables and internet gateways, check your own network first. A quick `curl -4` vs `curl -6` test would have revealed this in 30 seconds.

---

## Quick Diagnostic Cheat Sheet

If you're experiencing the same issue, run these four commands:

```bash
# 1. Do you have a public IPv4?
ip addr show | grep "inet "
# If you only see 10.x, 172.16.x, or 192.168.x → no public IPv4

# 2. Is IPv4 internet dead?
curl -4 https://checkip.amazonaws.com
# If this times out → you're on IPv6-only

# 3. Is IPv6 working?
curl -6 https://checkip.amazonaws.com
# If this returns an IP → NAT64 is your path to IPv4 internet

# 4. Verify DNS64 synthesis
nslookup <your-ec2-hostname>
# Look for a 64:ff9b:: address → that's DNS64 in action
```

If commands 1 and 2 fail but 3 and 4 work — you're on a NAT64/DNS64 network. Use hostnames everywhere, and you'll have no issues.

---

## Conclusion

What looked like an AWS networking bug turned out to be a fascinating window into how modern ISPs are handling IPv4 exhaustion. My entire internet connection runs over IPv6, with my ISP silently translating to IPv4 behind the scenes for destinations that don't support IPv6 yet.

The fix was simple — use the DNS hostname instead of the raw IP. But the understanding of *why* is what separates an engineer who can debug novel situations from one who just follows tutorials.

This kind of real-world debugging is exactly what I'm documenting as I work through a full AWS cross-region migration simulation. More posts coming as the project progresses.

---

*Part of an ongoing series documenting a simulated AWS cross-region migration from `us-east-1` to `eu-west-1`, built as a hands-on portfolio project.*
