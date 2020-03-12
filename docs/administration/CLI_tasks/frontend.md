# Managing frontends

{! backend/administration/CLI_tasks/general_cli_task_info.include !}

## Download the latest frontend

This downloads a snapshot of the latest Pleroma-FE for a given reference and writes it to the `frontends_dir`. In a default setup, this means that this snapshot will be served as the frontend by the backend.

```sh tab="OTP"
 ./bin/pleroma_ctl pleroma.frontend download [<options>]
```

```sh tab="From Source"
mix pleroma.frontend download [<options>]
```

### Options
- `--reference <reference>` - Specify the reference that will be downloaded. Defaults to `master`.
