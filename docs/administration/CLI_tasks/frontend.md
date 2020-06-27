# Managing frontends

`mix pleroma.frontend install kenoma --ref=stable`

`develop` and `stable` refs are special: they are not necessarily `develop` or
`stable` branches of the chosen frontend repo, but are smart aliases for either
default branch of a frontend repo (develop), or latest release in a repo (stable).

Only refs that have been built with Gitlab CI can be installed