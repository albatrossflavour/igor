# Driver Design

This maps the `./igor` driver: the orchestration backbone that replaces "everything through `bolt plan run igor::deploy`". It follows the Bolt boundary from `BOOTSTRAP-DESIGN.md` and the stages from `CHARTER.md`. Read those first.

## What the driver is

`./igor` stops being a thin wrapper that shells out to one mega Bolt plan. It becomes the conductor. It runs the charter's stages in order, and for each stage it calls the tool that actually fits: `tofu` for provisioning, the template script on the host, `git`/`gh` for the control repo, local puppet client tools for stage 5, and Bolt only for the node-configuration stages (4, 6, 8) where inventory and the peadm-family modules earn their place.

Bolt becomes one instrument in the orchestra, not the orchestra.

## The model

Each stage is a shell function in the driver. `deploy` runs them in order with gating. Every stage is also individually invocable, which the current all-Bolt design cannot do cleanly:

```text
./igor deploy                 # run all stages in order, with gating
./igor templates              # stage 1 only
./igor provision              # stage 2 only
./igor pe                     # stage 4 only
./igor infra                  # stage 6 only
./igor agents                 # stage 8 only
./igor setup                  # config wizard
./igor status | destroy | reset
```

Per-stage invocation matters for a demo and for debugging: you can rerun just the failed stage instead of the whole chain. Each stage is idempotent and safe to rerun (skip-if-present, matching the template script's per-item skip).

## Secrets model

Setup used to write `cipassword`, `console_password` and the Pihole password in plaintext into `terraform.tfvars`. It no longer writes or prompts for them anywhere. Igor reads secrets from environment variables and has no opinion on how they get there, whether that's a shell profile, a CI secret store, or typing `export` by hand.

- **Terraform and state backend secrets** are ordinary environment variables that tofu reads itself: `TF_VAR_proxmox_token_secret`, `TF_VAR_cipassword`, `TF_VAR_console_password`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. `terraform.tfvars` holds non-secret config only.
- **The template password** for stage 1 is the same `TF_VAR_cipassword`, handed to goodmountain over SSH stdin.
- **Puppet and PE secrets** stay in Hiera, eyaml-encrypted with `keys/`. Setup encrypts the console password from `TF_VAR_console_password`.

The list lives in `SECRET_VARS` in both `./igor` and `scripts/igor-setup.rb`. Both check it up front and name every missing variable, so a run fails before it starts, not halfway through an apply.

## Per-stage map (concrete)

| Stage                | Driver does                                                                                     | Tool            |
| -------------------- | ----------------------------------------------------------------------------------------------- | --------------- |
| 1 Templates          | scp goodmountain to the PVE host, pass `TF_VAR_cipassword` on stdin, run `template-generate.sh` | Driver (ssh)    |
| 2 Provision          | `tofu apply` with secrets from the environment                                                  | Driver (tofu)   |
| 3 Control repo       | `gh repo create`, clone template, seed from `data/`, push                                       | Driver (git/gh) |
| 4 PE primary         | `bolt plan run igor::build_pe`                                                                  | Bolt            |
| 5 Client tools       | fetch CA cert, `puppet access login`, write client configs                                      | Driver          |
| 6 Infra roles        | for each role with VMs: `bolt plan run igor::build_infra_node role=<r>`                         | Bolt            |
| 7 Integration tokens | reserved, no-op                                                                                 | Driver          |
| 8 Agents             | `bolt plan run igor::build_agents`                                                              | Bolt            |
| 9 Code deploy        | `puppet-code deploy production --wait`                                                          | Driver          |

The driver discovers which roles actually have VMs from `tofu output -json bolt_inventory` (via the existing `tofu_inventory` task or `jq` directly), so stage 6 only builds what stage 2 created, same as today's `deploy.pp` logic, just moved to the driver.

## What stays in Bolt

Three plans, invoked by the driver, plus their support:

- `igor::build_pe` (stage 4), cleaned up: strip out the control-repo bootstrap, CA cert, and access-login glue currently tangled inside it. Those move to driver stages 3 and 5.
- `igor::build_infra_node` (stage 6), already collapsed to one parameterised plan.
- `igor::build_agents` (stage 8).
- `inventory.yaml`, `hiera.yaml`, and the eyaml `keys/`, which the Bolt stages depend on.

Everything else in `plans/` becomes driver logic.

## What this supersedes from the interim work

Being honest about what the driver replaces, so we do not end up with two implementations of the same stage:

- `plans/build_templates.pp` (the Bolt SSH-staging plan we built this session) is superseded by the stage 1 driver function. The awkward parts (constructing a Target, uploading files, awk-scraping the password from tfvars) disappear. What carries over untouched: the skip and `force_rebuild` logic already in `template-generate.sh`, and the `igor::proxmox_host` config (`host`/`user`/`storage`/`work_dir`), now read by the driver instead of the plan. Remove `build_templates.pp` when the driver stage lands.
- `plans/deploy.pp` orchestration moves into the driver's `deploy` command. The plan goes away.
- `plans/setup.pp` (817 lines) breaks into driver phases: collect config, write `terraform.tfvars` (non-secrets), check the secret environment variables are set, ensure the eyaml keys exist, write `inventory.yaml`, `tofu init`. Not a Bolt plan.
- The ceremony plans (`bootstrap_control_repo`, `destroy_control_repo`, `configure_client_tools`, `fetch_ca_cert`, `puppet_access_login`) become driver functions.

## Decisions (settled)

1. **Config source: keep the split.** The driver reads `terraform.tfvars` and tofu outputs; the Bolt stages read Hiera as they do now. This accepts the existing duplication of domain and hostnames across the two, in exchange for less work and less risk. Unifying config is a possible later cleanup, not part of this rewrite.
2. **Secrets: environment variables only.** Igor does not integrate with any secret manager. It reads the `SECRET_VARS` list from the environment and fails early if any are missing. How the variables get populated is up to the operator, not Igor.
3. **Driver language: Ruby.** Initially bash (it matched the existing `./igor` entry point and is fine for sequencing subprocess calls), revised to Ruby. Setup went to Ruby first because it is interactive prompts plus crypto plus templating — bash's weak spot. The driver follows because the work still queued to move into it (stages 3 and 4: reading `console_password` from eyaml hiera, and the 448-line git/gh control-repo bootstrap) is the same Ruby-shaped logic, and even today role discovery shells out to `jq` and config reading to `awk`. Ruby is already a hard dependency (Bolt, eyaml, the tasks, setup), so it adds nothing to install, and porting the ~330-line bash driver now is cheaper than after it absorbs more. `./igor` stays the entry point (`#!/usr/bin/env ruby`), invoked exactly as before.
