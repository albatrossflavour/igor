# Bootstrap Redesign Map

This document maps Igor's bootstrapping against the charter before we commit to rewriting it. It exists to answer one question honestly: what is worth keeping, what is ceremony, and where does Bolt actually earn its place. See `CHARTER.md` for the scope this serves.

## Origin

Igor was assembled from two working repos: `proxform` (Terraform plus Proxmox template generation) and `peadm` (Puppet Enterprise builds, a set of thin shell scripts wrapping `bolt` commands). The `build_*.pp` plans are Bolt translations of `peadm`'s `build-*.sh`. The template script and `tf/` came from `proxform`. That history explains the duplication and the orphans we found.

## Verdict: what Igor got right, and what it got wrong

This matters because a blind rewrite would throw away the good decisions along with the mess.

### Keep (Igor improved on both sources)

- Terraform and Bolt are decoupled. `proxform` ran the PE builds from Terraform `local-exec` provisioners. Igor removed them, so Terraform state completes before Bolt runs and failed config no longer taints infrastructure. This is the right architecture and it stays.
- Dynamic, tag-based inventory. `bolt_inventory` output plus the `tofu_inventory` task replaced hardcoded targets. Both sources used static or hardcoded hostnames. Keep.
- Hiera-based targets instead of `peadm`'s hardcoded `puppet.lab.albatrossflavour.com`. Keep.
- Pihole DNS, control-repo lifecycle, Terraform outputs. Genuinely new value, present in neither source. Keep.
- The template script itself. Functionally identical to `proxform`'s, proven. Keep (with the conditional-skip improvement already added). It has since moved to its own repo, goodmountain, because nothing about it is Puppet specific.

### Fix (Igor regressed or over-reached)

- Secrets. `proxform` injected credentials at apply time with `op://` references via `run-terraform.sh` and never wrote plaintext. Igor dropped that and now writes `cipassword`, `console_password`, and `pihole_password` in plaintext into `terraform.tfvars` from the setup wizard. `load_1password_secrets.rb` still exists but is unused. This is a regression and it should be undone.
- Everything forced through Bolt. This is the source of the pain, detailed below.

## The Bolt boundary

Every plan sorts into one of two piles by a single test: does it call an external module against real targets, or does it `run_command` on localhost to launch another tool?

### Bolt earns its place (node-facing, uses inventory and the peadm-family modules)

- `build_pe` (stage 4): `peadm::install`, `code_manager`, `mkdir_p_file`, `puppet_runonce`
- `build_scm` / `build_cd4pe` / `build_dashboard` (stage 6): `agent_install`, CSR inserts, `install_from_config`, `puppet_runonce`
- `build_agents` (stage 8): `agent_install`, `puppet_runonce`
- `status` (node half): `complyadm::ctl`, `cd4peadm::ctl`

### Bolt is ceremony (localhost subprocess launching, no module or inventory benefit)

- `setup` (817 lines): the interactive wizard, entirely localhost scripting
- `bootstrap_control_repo` (448 lines), `destroy_control_repo`: git, gh, curl, eyaml on localhost
- `configure_client_tools`, `fetch_ca_cert`, `puppet_access_login`: local config writes and local puppet client calls
- `deploy`, `destroy_environment`, `destroy_agents`: `tofu` subprocess-launched
- `preflight`, `reset`: local bash checks and `rm`

Even `build_pe`, a legitimate Bolt plan, is polluted: it calls `bootstrap_control_repo` (git/gh), `fetch_ca_cert`, and `puppet_access_login`, and reads eyaml keys off local disk. Node config and localhost glue are tangled in one plan, which is why nothing feels cleanly separable.

## The external-module contract (the substrate that never gets rewritten)

The orchestration depends on exactly these external calls. Everything else is glue.

- `peadm::install`, `peadm::agent_install`, `peadm::util::insert_csr_extension_requests`, `peadm::code_manager`, `peadm::puppet_runonce`, `peadm::mkdir_p_file`
- `complyadm::install_from_config`, `complyadm::ctl`
- `cd4peadm::install_from_config`, `cd4peadm::ctl`

Eleven calls. That is the entire node-facing surface. The rewrite orchestrates these; it never reimplements them.

## Stage-by-stage map

For each charter stage: the proven substrate it calls, whether it belongs in Bolt or the driver, and what carries over.

| Stage                           | Substrate it calls                                       | Bolt or driver  | Notes                                                                                                                |
| ------------------------------- | -------------------------------------------------------- | --------------- | -------------------------------------------------------------------------------------------------------------------- |
| 1 Templates                     | goodmountain's `template-generate.sh` on the PVE host    | Driver          | Run the script on the host. The Bolt SSH-staging wrapper is ceremony. Keep the skip/force_rebuild logic.             |
| 2 Provision                     | `tf/` (kept, improved with outputs and DNS)              | Driver          | Run `tofu` directly with `op://` injection restored (proxform's `run-terraform.sh` pattern). Not a Bolt plan.        |
| 3 Control repo                  | git, gh                                                  | Driver          | `bootstrap_control_repo` is 448 lines of git/gh. A shell function, not a Bolt plan.                                  |
| 4 PE primary                    | `peadm::install`, `code_manager`, `mkdir_p_file`         | Bolt            | Earns it. Strip out the control-repo bootstrap, CA cert, and access-login glue tangled inside it.                    |
| 5 Client tools                  | local puppet-access / puppet-code                        | Driver          | `fetch_ca_cert`, `puppet_access_login`, `configure_client_tools` are three localhost scripts. Merge into the driver. |
| 6 Infra roles                   | `agent_install`, `install_from_config`, `puppet_runonce` | Bolt            | Collapse the near-identical plans into one parameterised flow driven by the hiera role table.                        |
| 7 Integration tokens (reserved) | PE RBAC API, eyaml                                       | Driver (mostly) | Reserved slot, no consumer since Nessus was removed. Kept for future external-tool integrations.                     |
| 8 Agents                        | `agent_install`, `puppet_runonce`                        | Bolt            | Earns it. Same parameterised shape as stage 6.                                                                       |
| 9 Code deploy                   | `peadm::code_manager` or `puppet-code deploy`            | Driver          | One command.                                                                                                         |

Lifecycle verbs follow the same rule: `setup` and `preflight` become driver scripts (not an 817-line plan), `status` splits (Bolt for the node query, driver for the tofu part), `reset` and `destroy` are driver-side tofu and rm, with the agent purge staying in Bolt.

## Shape of the result

The `./igor` script stays as the single entry point, but stops routing everything through `bolt plan run igor::deploy`. Instead it orchestrates the phases and calls the right tool for each: `tofu` directly for provisioning and teardown (with `op://` secrets), the template script on the host, `git`/`gh` for the control repo, local puppet client tools for stage 5, and Bolt only for the node-configuration stages (4, 6, 8) where inventory and the peadm-family modules pull their weight.

Of roughly nineteen current plans, about five stay as Bolt (cleaned up, with the three stage-6 duplicates collapsed to one). The rest become driver logic.

## Recommendation on topology

Rebuild in place, do not start a fresh repo. The map shows why: Igor's keepers (TF decoupling, dynamic inventory, hiera targets, DNS, tofu outputs, the control-repo template, the eyaml keys, the charter) are exactly the parts a fresh repo would have to re-derive from scratch. The mess is concentrated in `plans/` and the secrets handling, both of which can be rewritten on a branch without disturbing the substrate. A fresh repo pays full price to recover work Igor already got right.
