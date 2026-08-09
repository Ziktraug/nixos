# Git identity and SSH configuration

The public Git module installs Git, maps `modules/devtools/git/gitconfig` to
`~/.gitconfig`, and maps the global ignore file. It intentionally contains no
name, email address, organization, or SSH key path.

## Private identity layer

The managed `~/.gitconfig` includes `~/.gitconfig.private`. Create that file
locally and keep it outside public repositories:

```gitconfig
[user]
    name = Alice Example
    email = alice@example.com
```

Directory-specific identities can live in separate local files:

```gitconfig
# ~/.config/git/work.gitconfig
[user]
    name = Alice Example
    email = alice@example.com

[core]
    sshCommand = ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519-work
```

Reference the local file from `~/.gitconfig.private`:

```gitconfig
[includeIf "gitdir:~/Projects/work/"]
    path = ~/.config/git/work.gitconfig
```

This keeps reusable Git behavior public while leaving every real identity and
credential under local control.

## SSH key setup

Generate a dedicated key and set restrictive permissions:

```bash
ssh-keygen -t ed25519 -C "alice@example.com" -f ~/.ssh/id_ed25519-work
chmod 600 ~/.ssh/id_ed25519-work
chmod 644 ~/.ssh/id_ed25519-work.pub
```

Add only the public key to the relevant Git provider. Test the connection with
the matching provider hostname, for example:

```bash
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519-work -T git@github.com
```

SSH keys are never managed by this repository.

## Verification

The verifier reads its expectations from a config path instead of embedding an
identity:

```bash
./script/verify-git-ssh.sh ~/.config/git/work.gitconfig
```

The same path can be supplied through `GIT_SSH_CONFIG_SOURCE`. Set
`GIT_REPOSITORY_ROOT` when repositories are stored somewhere other than the
default project directory.

Useful diagnostics:

```bash
git config --show-origin --get user.email
git config --show-origin --get core.sshCommand
```

If Git selects the wrong identity, verify that the `includeIf` directory ends
with `/` and that its referenced config exists. If SSH rejects the key, check
its permissions and confirm that its public half is registered with the
provider.
