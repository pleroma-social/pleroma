# Config versioning

Database configuration supports simple versioning. Every change (list of changes or only one change) through adminFE creates new version with backup from config table. It is possible to do rollback on N steps (1 by default). Rollback will recreate `config` table from backup.

**IMPORTANT** Destructive operations with `Pleroma.ConfigDB` and `Pleroma.Config.Version` must be processed through `Pleroma.Config.Versioning` module for correct versioning work, especially migration changes.

Example:

* new config setting is added directly using `Pleroma.ConfigDB` module
* user is doing rollback and setting is lost

## Creating new version

Creating new version is done with `Pleroma.Config.Versioning.new_version/1`, which accepts list of changes. Changes can include adding/updating/deleting operations in `config` table at the same time.

Process of creating new version:

* saving config changes in `config` table
* saving new version with current configs
  * `backup` - keyword with all configs from `config` table (binary)
  * `current` - flag, which marks current version (boolean)

## Version rollback

Version control also supports a simple N steps back mechanism.

Rollback process:

* cleaning `config` table
* splitting `backup` field into separate settings and inserting them into `config` table
* removing subsequent versions

## Config migrations

Sometimes it becomes necessary to make changes to the configuration, which can be stored in the user's database. Config versioning makes this process more complicated, as we also must update this setting in versions backups.

Versioning module contains two functions for migrations:

* `Pleroma.Config.Versioning.migrate_namespace/2` - for simple renaming, e.g. group or key of the setting must be renamed.
* `Pleroma.Config.Versioning.migrate_configs_and_versions/2` - abstract function for more complex migrations. Accepts two functions, the first one to make changes with configs, another to make changes with version backups.
