---
layout: post
title: How to really make use of `kubectl debug`
categories: [Technical]
tags: [debugging, kubernetes]
---


So I had ==CockroachDB== deployed on my kind cluster. So the thing is its deployed as a **statefulset**. I don't really know the internal working of CockroachDB.

I was going through [Community Forum](https://www.cockroachlabs.com/docs/stable/cluster-setup-troubleshooting#authentication-issues) of CockroachDB, and I was going through Client Connection Issues, the different things that needs to tested/checked.

```bash
❯ kg svc
NAME                            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)              AGE
my-release-cockroachdb          ClusterIP   None           <none>        26257/TCP,8080/TCP   4h44m
my-release-cockroachdb-public   ClusterIP   10.96.85.228   <none>        26257/TCP,8080/TCP   4h44m
```

Infact, cockroachDB is exposed as a **headless service**, (ClusterIP = None).

> Pods identify  each other using **FQDN** (e.g., `cockroachdb-0.cockroachdb.default.svc.cluster.local`). If DNS or the Headless Service is misconfigured, they can't see each other, the cluster never "initializes," and the health check returns 503.

```bash
# Discovery : Check if one pod can see the other pod
kubectl exec -it cockroachdb-0 -- nslookup cockroachdb-1.cockroachdb

;; Got recursion not available from 10.96.0.10
Server:		10.96.0.10
Address:	10.96.0.10#53

Name:	my-release-cockroachdb-1.my-release-cockroachdb.ckdb.svc.cluster.local
Address: 10.244.1.14
;; Got recursion not available from 10.96.0.10
```

- **If the above works but  still get i/o timeout:** You likely have a **NetworkPolicy** or **Firewall** blocking port `26257` (internal gossip) or `8080` (HTTP health).

> Standard database images like CockroachDB are often "**distroless**" or heavily hardened, meaning they lack a shell (`sh`, `bash`) and package managers (`apt`, `yum`) to reduce the attack surface.

Run this command to drop a "Netshoot" container (the Swiss Army knife of networking) into any failing pod:

```bash
k debug -it my-release-cockroachdb-0 \
  --image=nicolaka/netshoot \
  --target=db \
  --profile=general \
  -- sh
```

**Once inside that shell, try these three tests:**

1. **DNS Test:** Check if it can find its neighbor. `nslookup my-release-cockroachdb-1.my-release-cockroachdb`
2. **Port Test:** See if the neighbor is listening. `nc -zv my-release-cockroachdb-1.my-release-cockroachdb 26257`
3. **Local Check:** See what CockroachDB is doing on the local ports. `ss -tulpn`


> When you set `clusterIP: None`, the FQDN `my-svc.namespace.svc.cluster.local` resolves to a **list of all the individual Pod IPs** currently backing that service.
>
> In case of `clusterIP: 10.96.1.12` you get a stable FQDN like `my-svc.namespace.svc.cluster.local`. This resolves to a single **Virtual IP** (the ClusterIP).

## CheatSheet

-  **Ephemeral container debugging**
   - API call made: `PATCH /pods/<name>/ephemeralcontainers`
   - No *PodSpec* mutation
   -  Use when you need need same namespaces (network, PID)
   - You can access the file-system using of target container :  `/proc/<PID>/root`
```bash
k debug -it my-release-cockroachdb-0 \
  --image=nicolaka/netshoot \
  --target=db \
  --profile=general \
  -- sh
```
- **Pod-copy debugging**
	- Copies: Volumes, Env vars, Security context
```bash
kubectl debug pod/<pod-name> \
  --copy-to=<new-pod-name> \
  --set-image=*=busybox \
  --share-processes \
  -it
```
- **Node debugging**
- Use when : kubelet is alive,  Node networking/storage broken, CNI/CSI/kube-proxy issues.
- Under the hood creates a Pod where
	- `hostPID: true`
	- `hostNetwork: true`
	- `/` mounted at `/host`
```bash
kubectl debug node/<node-name> \
  -it \
  --image=busybox
```


| Pod State                  | Ephemeral container | Pod copy    | Node debug | Why                                         |
| -------------------------- | ------------------- | ----------- | ---------- | ------------------------------------------- |
| **Running + Ready**        | ✅ Best              | ⚠️ Overkill | ❌          | Everything already works                    |
| **Running + NotReady**     | ✅                   | ⚠️          | ❌          | Debug probes / app health                   |
| **CrashLoopBackOff**       | ⚠️ Sometimes        | ✅ Best      | ❌          | Container restarts too fast                 |
| **OOMKilled**              | ❌ Mostly useless    | ✅ Required  | ❌          | Container already dead                      |
| **ImagePullBackOff**       | ❌                   | ❌           | ❌          | Pod never runs                              |
| **Pending**                | ❌                   | ❌           | ⚠️         | Scheduling problem                          |
| **InitContainerCrashLoop** | ❌                   | ✅           | ❌          | Ephemeral containers attach only after init |
| **Completed (Succeeded)**  | ⚠️                  | ✅           | ❌          | App already exited                          |
| **Evicted**                | ❌                   | ❌           | ⚠️         | Pod gone                                    |
| **PodDeleted**             | ❌                   | ❌           | ⚠️         | No object to patch                          |

## Common Error Encountered

-  **i/o timeout:** This means that the **internal** CockroachDB process is trying to reach other pods and failing.
-  **503 Error**: This is the kubelet telling you: "I tried to ping the CockroachDB health endpoint (usually /_admin/v1/health)_, but the database told me it's not ready to take traffic."
