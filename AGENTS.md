# AGENTS.md

## Purpose

This repository manages a complete, portable development environment.

It provides:

- portable dotfiles
- development tooling
- a reproducible Linux development container
- installation and bootstrap tooling
- Pi agent configuration and extensions

The environment must support:

- native Linux
- Linux containers using Podman on Linux
- Linux containers using Podman on Windows

The dotfiles must remain usable independently of the container.

## Repository architecture

The target repository structure is:

```text
.
├── dotfiles/
│   ├── .config/
│   │   ├── nvim/
│   │   ├── tmux/
│   │   ├── git/
│   │   │   └── config
│   │   ├── pi/
│   │   └── ...
│   ├── .bashrc
│   ├── .zshrc
│   ├── .profile
│   └── ...
│
├── container/
│   ├── Containerfile
│   └── devcontainer.json
│
├── scripts/
│   ├── install/
│   ├── container/
│   └── ...
│
├── bin/
│   └── ...
│
├── Makefile
├── AGENTS.md
├── README.md
└── .gitignore
```

`dotfiles/` contains configuration that can be installed directly onto a Linux host.

`container/` defines the Linux development environment.

`scripts/` contains installation, bootstrap, validation, and environment-management implementation.

`bin/` contains user-facing utilities.

`Makefile` provides the high-level interface for repository operations.

`AGENTS.md` defines how an agent should work with this repository.

Do not move application configuration into the container configuration merely because the container uses it.

## Source of truth

The repository is the source of truth for the development environment.

The same dotfiles must work on native Linux and inside the development container wherever practical.

Do not maintain separate copies of the same configuration for:

- host Linux
- container Linux
- Windows
- WSL

Handle environment-specific behaviour at the appropriate boundary.

Application configuration belongs in `dotfiles/`.

Container-specific configuration belongs in `container/`.

Installation and bootstrap logic belongs in `scripts/`.

High-level workflows belong in `Makefile`.

## Dotfiles

The dotfiles must work without the development container.

Install them into standard locations using symlinks where appropriate.

For example:

```text
dotfiles/config/nvim → ~/.config/nvim
dotfiles/config/tmux → ~/.config/tmux
dotfiles/config/pi   → ~/.config/pi
```

Do not maintain copied versions of the configuration.

Installation must be idempotent.

Running installation repeatedly must converge on the desired state.

Installation must not silently overwrite unrelated existing user configuration.

Handle conflicting files explicitly.

Do not hard-code usernames, hostnames, absolute home directories, Windows drive letters, or repository paths.

Use `$HOME`, XDG variables, and other appropriate environment variables.

## Native Linux workflow

The supported native workflow is:

1. Clone the repository.
2. Run the repository installation workflow.
3. Install or link the dotfiles.
4. Install required development tools.
5. Use the environment directly on Linux.

The `Makefile` should provide the high-level command for this workflow.

The implementation belongs in `scripts/`.

Native installation must not require Podman.

## Container workflow

The supported container workflow is:

1. Clone the repository.
2. Build the development image.
3. Create or start the development container.
4. Mount the required workspace.
5. Install or link the repository's dotfiles inside the container.
6. Use the Linux development environment.

The container must be reproducible.

Do not manually configure a running container when the change should persist in newly created containers.

If a configuration or package is required for the environment, encode it in the repository.

The container should be disposable.

Persistent source code and configuration should remain outside the container where practical.

## Podman

Use Podman as the container runtime.

Do not assume Docker is installed.

Container workflows should expose high-level Make targets rather than requiring users to remember long Podman commands.

The repository should provide workflows for:

- building the image
- starting the development container
- entering the container
- stopping the container
- removing the container
- rebuilding after container-definition changes

Keep the actual Podman implementation in the appropriate Make target or script.

Do not duplicate Podman commands across multiple files.

The repository must not require Podman when the user only wants to install the dotfiles on native Linux.

## Containerfile

`container/Containerfile` defines the development environment.

It should contain the system-level dependencies required by the general development environment.

It should not contain dependencies belonging to an individual project.

Do not turn the image into a collection of arbitrary development tools.

Keep the image reproducible and reasonably small.

When changing the `Containerfile`:

1. Build the image.
2. Start the container.
3. Verify required tools.
4. Verify dotfile installation.
5. Verify the development environment works without manual post-build configuration.

## Dev container

`container/devcontainer.json` defines how a compatible development client uses the development container.

It should use the repository's `Containerfile`.

Do not create a second independent environment in `devcontainer.json`.

Do not duplicate package installation between `Containerfile` and `devcontainer.json` unless the distinction is required by the tooling.

The `Containerfile` defines the environment.

The devcontainer configuration defines how a development client launches and connects to that environment.

## Makefile

The `Makefile` is the primary high-level interface for repository operations.

Before creating a new target, inspect existing targets.

Use Make targets for repeatable workflows such as:

- installation
- validation
- container build
- container lifecycle
- shell access
- testing
- cleanup

The exact target names should reflect the actual repository implementation.

Make recipes should remain thin.

Put substantial implementation logic in scripts.

Do not turn the Makefile into a large shell program.

Targets should work from the repository root and should not depend on the user's current working directory.

## Scripts

Scripts implement concrete repository operations.

Keep each script focused on one responsibility.

Scripts should:

- fail clearly
- use appropriate error handling
- work from the repository root
- avoid unnecessary global state
- be idempotent where applicable

Before creating a script, inspect existing scripts and Make targets.

Do not create a new script when an existing script should own the functionality.

If a script grows to contain multiple unrelated responsibilities, refactor it.

## Application configuration

Each application owns its configuration inside `dotfiles/`.

For example:

```text
dotfiles/config/nvim/
dotfiles/config/tmux/
dotfiles/config/pi/
```

Do not duplicate detailed application configuration in `AGENTS.md`.

Do not put individual keybindings, plugin lists, status-bar settings, Pi extensions, or other application-specific behaviour in this file.

The application's configuration is the source of truth for that application's behaviour.

When changing application configuration, inspect the complete relevant configuration before modifying it.

## Agent operating procedure

Any coding agent working on this repository must treat it as an engineering project rather than a collection of immutable dotfiles.

Agents may:

- create new files
- create new scripts
- create new configuration
- refactor existing code
- move files
- rename files
- replace implementations
- remove obsolete code
- change the repository architecture

Existing implementation does not automatically define the correct architecture.

For every non-trivial task, the agent should:

1. Understand the requested behaviour.
2. Identify which part of the repository owns the responsibility.
3. Inspect relevant existing implementation.
4. Search for related functionality before creating anything new.
5. Determine whether to extend, refactor, replace, or create.
6. Implement the change.
7. Remove obsolete implementation when appropriate.
8. Validate the result.

Do not create a new script, helper, abstraction, configuration file, or dependency simply because it provides a convenient place for the new functionality.

Do not preserve poor architecture merely because it already exists.

When existing functionality should change to support the requirement, refactor it.

When a responsibility genuinely has no existing owner, create an appropriate component.

Agents should use the repository's Make targets, scripts, and documented workflows rather than inventing alternative procedures.

Agents must inspect the relevant repository files before assuming how a workflow operates.

Agents must not rely on instructions from a previous conversational context when the repository can provide the authoritative information.

## Architectural ownership

Use these boundaries when deciding where functionality belongs:

```text
User/application configuration
    → dotfiles/

Container environment
    → container/

Installation/bootstrap
    → scripts/

High-level repository workflows
    → Makefile

User-facing development utilities
    → bin/

Pi configuration and extensions
    → dotfiles/config/pi/
```

Do not put functionality into a component merely because it is convenient.

Do not force unrelated responsibilities into an existing file to avoid creating a new component.

## Reuse and refactoring

Search before creating.

If existing functionality performs most of the required work, extend it.

If existing functionality has the wrong structure, refactor it.

If existing functionality is obsolete, replace and remove it.

Do not create parallel implementations that perform the same responsibility.

After moving or renaming something, search for stale references.

After replacing something, remove the old implementation unless compatibility explicitly requires it.

The final repository should have one clear implementation for each responsibility.

## Dependencies

Before adding a dependency:

1. Check whether the required functionality already exists.
2. Check whether the operating system provides it.
3. Check whether an existing configured tool provides it.
4. Consider startup and runtime cost.
5. Consider maintenance.
6. Consider portability.
7. Add it only when it provides a meaningful benefit.

Prefer native functionality over additional dependencies when both provide a suitable solution.

Do not add project-specific dependencies to the general development container.

## Cross-platform behaviour

The development environment targets Linux.

The host may be Windows or Linux.

Do not make application configuration depend on Windows-specific paths or commands.

When host-specific behaviour is unavoidable, isolate it at the host/container integration boundary.

Do not duplicate application configuration to solve a host integration problem.

Use portable commands where practical.

Expose platform-specific operations through repository scripts or Make targets.

## Security

Never commit:

- passwords
- API keys
- access tokens
- private keys
- credentials
- authentication state
- machine-specific secrets

Do not expose host credentials to containers or agents unless explicitly required.

Do not expose the Podman socket or other privileged host interfaces unless the repository explicitly requires container management from inside the environment.

Use environment variables or ignored local configuration for secrets.

## Validation

Validate changes using the narrowest relevant mechanism first.

For dotfiles:

- validate the affected application's configuration
- start the affected application where practical

For scripts:

- run the script
- run it again where idempotency applies

For the container:

- build the image
- start the container
- verify required tools
- verify dotfile installation
- verify the development environment

For Makefile changes:

- run the affected target from the repository root

For structural changes:

- search for stale references
- remove obsolete files
- check for duplicate implementations

Do not claim a change works without performing the relevant validation when the environment allows it.

## Documentation

Update documentation when a supported workflow changes.

Document:

- installation
- native Linux usage
- container usage
- supported host/container arrangements
- important maintenance workflows
- troubleshooting

The Makefile and scripts are the executable source of truth for commands.

Do not maintain contradictory command examples in documentation.

## Change discipline

Do not perform unrelated cleanup during a task.

Do not optimise for the smallest possible diff when a larger refactor produces the correct architecture.

Do not leave temporary scripts, debug configuration, generated files, experimental dependencies, or obsolete implementations behind.

A completed change should leave the repository internally consistent, reproducible, and ready for another agent to continue working on.
