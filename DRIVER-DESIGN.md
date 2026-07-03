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

This is the regression fix. Today `setup` writes `cipassword`, `console_password`, and `pihole_password` in plaintext into `terraform.tfvars`. Restore the `op://` pattern that `load_1password_secrets.rb` already encodes. The clean split is three-way:

- **Terraform secrets** live in 1Password, injected at apply time. `terraform.tfvars` holds non-secret config only (domain, api_url, storage, enable flags, counts). Secrets never touch disk.
- **The template password** (`cipassword`) is read from 1Password at stage 1, not scraped from tfvars.
- **Puppet and PE secrets** stay in Hiera, eyaml-encrypted with `keys/`. This side was always correct and does not change.

The driver injects Terraform secrets with an `op run` env-file, so the values only exist in the subprocess environment:

```bash
# tf/providers/proxmox/secrets.env  (op:// references, safe to commit)
TF_VAR_proxmox_password=op://proxtoboltfu/proxmox-credentials/password
TF_VAR_pe_console_password=op://proxtoboltfu/pe-credentials/console_password
TF_VAR_sudo_password=op://proxtoboltfu/pe-credentials/sudo_password
TF_VAR_forge_token=op://proxtoboltfu/pe-credentials/forge_token
AWS_ACCESS_KEY_ID=op://proxtoboltfu/aws-s3-backend/access_key_id
AWS_SECRET_ACCESS_KEY=op://proxtoboltfu/aws-s3-backend/secret_access_key

# driver wrapper
tofu_apply() {
  op run --env-file=tf/providers/proxmox/secrets.env -- \
    sh -c 'cd tf/providers/proxmox && tofu apply -auto-approve -parallelism=1'
}
```

The env-file holds `op://` references, not secrets, so it can be committed. This is exactly what `load_1password_secrets.rb` does, moved to where it belongs and actually used.

## Per-stage map (concrete)

| Stage                | Driver does                                                                                     | Tool            |
| -------------------- | ----------------------------------------------------------------------------------------------- | --------------- |
| 1 Templates          | `op read` the cipassword, stage the script to the PVE host, run `template-generate.sh` over SSH | Driver (ssh)    |
| 2 Provision          | `op run -- tofu apply` with the env-file; wait for DNS                                          | Driver (tofu)   |
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
- `plans/setup.pp` (817 lines) breaks into driver phases: collect config, write `terraform.tfvars` (non-secrets), ensure the 1Password items and eyaml keys exist, write `inventory.yaml`, `tofu init`. Not a Bolt plan.
- The ceremony plans (`bootstrap_control_repo`, `destroy_control_repo`, `configure_client_tools`, `fetch_ca_cert`, `puppet_access_login`) become driver functions.

## Decisions (settled)

1. **Config source: keep the split.** The driver reads `terraform.tfvars` and tofu outputs; the Bolt stages read Hiera as they do now. This accepts the existing duplication of domain and hostnames across the two, in exchange for less work and less risk. Unifying config is a possible later cleanup, not part of this rewrite.
2. **1Password provisioning: create if missing.** `setup` prompts for each Terraform secret and runs `op item create` in the `proxtoboltfu` vault when the `op://` reference does not resolve, so a fresh demo is turnkey. Existing items are left alone. (The vault is still named `proxtoboltfu` from the pre-rename; renaming it to `igor` is an optional tidy-up that would touch the `op://` paths in `secrets.env` and `load_1password_secrets.rb`.)
3. **Driver language: Ruby.** Initially bash (it matched the existing `./igor` entry point and is fine for sequencing subprocess calls), revised to Ruby. Setup went to Ruby first because it is interactive prompts plus crypto plus templating — bash's weak spot. The driver follows because the work still queued to move into it (stages 3 and 4: reading `console_password` from eyaml hiera, and the 448-line git/gh control-repo bootstrap) is the same Ruby-shaped logic, and even today role discovery shells out to `jq` and config reading to `awk`. Ruby is already a hard dependency (Bolt, eyaml, the tasks, setup), so it adds nothing to install, and porting the ~330-line bash driver now is cheaper than after it absorbs more. `./igor` stays the entry point (`#!/usr/bin/env ruby`), invoked exactly as before.
