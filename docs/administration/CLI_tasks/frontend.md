# Managing frontends

`mix pleroma.frontend install <frontend> [--path <path>] [--develop] [--ref <ref>]`

Frontend can be installed either from local path with compiled sources, or from web.

If installing from web, make sure you have [yarn](https://yarnpkg.com/getting-started/install)
since it's needed to build frontend locally. When no `--develop` or `--ref <ref>`
options passed, latest stable frontend will be installed.

If installing from local path, building of sources is up to you.

Currently supported `<frontend>` values:
- [admin](https://git.pleroma.social/pleroma/admin-fe)
- [kenoma](http://git.pleroma.social/lambadalambda/kenoma)
- [mastodon](http://git.pleroma.social/pleroma/mastofe)
- [pleroma](http://git.pleroma.social/pleroma/pleroma-fe)

## Example installation from local path
The complete process of installing frontend from local path would be following:
- download a frontend:

```bash
git clone https://git.pleroma.social/pleroma/pleroma-fe.git
```
- build the frontend
```bash
cd pleroma-fe && yarn && yarn build
```
- run the following command inside your Pleroma instance root directory:
```bash
mix pleroma.frontend install pleroma --path /path/to/pleroma-fe
```

## Example installation from web
The complete process of installing frontend from web would be following:
- make sure you've got `yarn` installed:

```bash
yarn -v
```

- run the following command inside your Pleroma instance root directory to
install latest develop frontend:
```bash
mix pleroma.frontend install pleroma --develop
```