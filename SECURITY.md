# Security policy

## Reporting a vulnerability

Report it privately, through GitHub's "Report a vulnerability" button on this repository's
Security tab (private vulnerability reporting). Do not open a public issue. Include what you
found, how to reproduce it, and what it lets an attacker do.

In scope: anything in this repository that makes the stack less safe than the README's "Security
posture" section says, for example a way for a job in a runner pod to reach the host, the LAN,
other pods, the GitHub credential or the Kubernetes API with any privilege, or a default that
exposes something. (That a pod can open a connection to its own node's ports is documented
Kubernetes behaviour, not a finding by itself.)

Out of scope here (report them upstream): vulnerabilities in k3s, Kubernetes, the Actions Runner
Controller, the GitHub Actions runner, Squid or Docker themselves.

## What you should know before running this

- **The k3s container is privileged.** A Kubernetes node inside Docker needs `privileged: true`,
  which makes the container equivalent to root on the host: every capability, every device, no
  seccomp or AppArmor confinement, a writable `/proc/sys`. Jobs do not run as the node; they run
  in pods under it, as an unprivileged user with no capabilities, under Pod Security `restricted`,
  without a Kubernetes API credential, and with network access only to the cluster DNS, the proxy
  and (as Kubernetes always allows) their own node. Through the proxy a job can send anything it
  can read to any public host. A kernel exploit from a
  pod, or a pod template that a person loosens, still ends at host root.
- **The kubelet changes host-wide kernel settings** (`vm.overcommit_memory`, `vm.panic_on_oom`,
  `kernel.panic`, `kernel.panic_on_oops` and two key-quota settings), and there is no way to run
  the stack with your own values: with `--protect-kernel-defaults` the kubelet refuses to start
  unless they are already set to its values. Running this stack means a kernel oops reboots the
  host after 10 seconds. The values stay set after `docker compose down` until a reboot or a
  manual reset; the README's "Security posture" section gives the commands.
- **Use it for private repositories only.** Pull requests from forks of a public repository could
  run arbitrary code on your host.
- **Credentials.** The GitHub credential is stored only in Kubernetes Secrets: the one
  `scripts/register.sh` creates from a file or a prompt, and the copy ARC's controller mirrors
  into `arc-systems` for each scale set's listener. The kubeconfig in `kubeconfig/` is a cluster-admin
  credential; keep it on the host. Neither ever belongs in git; `.gitignore` excludes `.env`,
  `kubeconfig/`, `*.token` and `*.pem`.
