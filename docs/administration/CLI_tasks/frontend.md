# Managing frontends

`mix pleroma.frontend install <frontend> --path <path>`


Install locally built frontend.

Currently supported `<frontend>` values:
- [admin](https://git.pleroma.social/pleroma/admin-fe)
- [kenoma](http://git.pleroma.social/lambadalambda/kenoma)
- [mastodon](http://git.pleroma.social/pleroma/mastofe)
- [pleroma](http://git.pleroma.social/pleroma/pleroma-fe)

The complete process of installing frontend would be following:
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