# Igor Charter

This document records what Igor is for, where its scope starts and stops, and the order in which it does its work. It exists to settle "does this belong in Igor" arguments before they turn into code. If a change does not serve the mission below, or crosses one of the boundaries, it does not go in.

## Mission

Take a barebones Proxmox host and stitch together a fully functioning Puppet Enterprise environment, including the control repo, from a single command. One operator, one `./igor deploy`, empty hypervisor to working PE with agents reporting in.

The operative word is stitch. Igor is not a configuration management tool and it is not a cloud abstraction. It is the integration layer that wires together tools which do not natively know about each other: OpenTofu, Proxmox, Pihole, peadm, complyadm, cd4peadm, and GitHub. Each of those does one job. Igor owns the ordering, the handoffs, and the shared truth (Hiera plus `r10k_remote`) that makes them behave as one system.

## Start state

Barebones means a Proxmox host that is:

- installed and reachable over SSH
- backed by storage (Ceph)
- configured with networking (the `vmbr1` bridge)
- empty of everything else

Igor does not install Proxmox, Ceph, or the network bridges. It assumes that base exists. Everything from operating system templates onward is Igor's responsibility.

## End state

A run leaves behind:

- Proxmox VM templates for the enabled operating systems
- VMs provisioned with static IPs and DNS records
- a Puppet Enterprise primary installed and configured via peadm
- working local client tools (CA cert imported, console login enabled)
- a control repo created on GitHub, seeded from Igor's data, both branches pushed and code deployed
- supporting infrastructure built and classified by role: SCM/Comply, CD4PE, Dashboard
- agent nodes built, classified via trusted facts, and converged

## Stages

This is the spine. Every artefact in the repo should map to one of these stages or be removed.

0. Build Proxmox templates (host-side, on the PVE host, conditional). Produces named templates.
1. Provision VMs and DNS (OpenTofu plus Proxmox plus Pihole). Clones the templates from stage 0.
2. Build the PE primary (peadm).
3. Configure local client tools (CA cert, console login).
4. Bootstrap the control repo on GitHub, seeded from Igor's data.
5. Build supporting infrastructure in parallel: SCM, CD4PE, Dashboard.
6. Reserved: external-tool integration tokens (for example PE RBAC tokens). No consumer at present (it previously held the Nessus token); kept as a slot for future integrations.
7. Build and classify agent nodes.
8. Deploy control repo code (`puppet-code deploy production`).

Alongside the build path sit the lifecycle verbs, which exist for the operator rather than as part of a deploy: `setup`, `preflight`, `status`, `reset`, `destroy`.

## Stage 0: template building

Template building is on the critical path, but it is conditional. The scope is "Igor can build templates". The behaviour is "Igor builds the templates that are missing". Those are not the same sentence, and the second one is what keeps `./igor deploy` usable day to day.

There is one canonical builder. Any duplicate or half-finished alternative is a hazard, because a second implementation drifts from the first on VMID numbering and produces templates that stage 1 cannot find.

### Gating

Two independent switches control the stage.

Per-template existence check (default, idempotent). Before building each template, check whether it already exists on the host. If it does, skip it and move on. On any given run some templates exist and some do not, so this check is per template, not per run: the ones that exist are skipped and any new one is built, in the same pass.

Argument gates (overrides), exposed on the plan and through the `./igor` wrapper:

- `build_templates` (default `true`): whether to run stage 0 at all. Set `false` when the host is known to be prepped and you do not want to SSH in and check.
- `force_rebuild` (default `false`): destroy and rebuild even when a template already exists. Use it when an upstream cloud image has been refreshed.

Behaviour summary:

| Invocation                            | Result                                                |
| ------------------------------------- | ----------------------------------------------------- |
| `./igor deploy`                       | build missing templates, skip existing, then continue |
| `./igor deploy build_templates=false` | skip stage 0 entirely                                 |
| `./igor deploy force_rebuild=true`    | rebuild all templates from fresh images               |

The destroy-and-recreate path only fires under `force_rebuild`. Default runs never tear down a template that already exists.

### Targeting the hypervisor

Stage 0 runs on the Proxmox host itself, which is not in the OpenTofu inventory because Igor did not create it. It needs a static target: a `proxmox_host` value in Hiera and a matching inventory entry, so a Bolt plan can reach the host over SSH and run the builder. This is a distinct concept from the dynamic, tofu-driven inventory groups used by every later stage.

### Template naming is a contract

Stage 1 clones templates by name (for example `template-Ubuntu-2404`). Those names, and the VMIDs the builder assigns, are the interface between stage 0 and stage 1. They must agree, the same way `bolt_inventory` is the contract between OpenTofu and the inventory task. A single builder makes this contract trivial to keep; multiple builders break it silently.

## What Igor does not do

Stating the exclusions is half the value of a charter.

- Agent-side configuration. That is the control repo's job, at runtime, via Code Manager. Igor creates and seeds the control repo, then gets out of the way.
- Day-2 drift management. Igor builds the environment. Keeping it correct afterwards is Puppet's job.
- Multi-cloud. Proxmox is the implementation. The provider contract under `tf/providers/_contract/` is a marker for a possible second provider, not a promise to be provider-agnostic today.
- Hypervisor provisioning. Igor assumes Proxmox, Ceph, and networking already exist. It builds templates on the host but does not install or configure the host.
