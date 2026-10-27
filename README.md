# Smallstep CLI and step-ca OCI image

Nix-built x86_64 Linux image and step CLI using the pinned Nixpkgs step-ca 0.30.2 and step CLI 0.31.0 packages. The standalone CLI is the same derivation included in the image.

## Build

```sh
nix flake check
nix build .#step
nix build .#image
```

## Upstream Dockerfile baseline

The version-matched [Dockerfile](https://raw.githubusercontent.com/smallstep/certificates/v0.30.2/docker/Dockerfile) uses the step CLI base, includes the cloud KMS plugin, runs as `step`, mounts `/home/step`, and starts `step-ca --password-file /home/step/secrets/password /home/step/config/ca.json`. Its [entrypoint](https://raw.githubusercontent.com/smallstep/certificates/v0.30.2/docker/entrypoint.sh) can initialize a CA from environment variables and prints the generated provisioner password once.

This image keeps the paths, service command, step CLI, KMS plugin, command override behavior, port, and `step ca health` check. It deliberately omits automatic CA initialization and password generation: provision the CA and provide its config, signing material, password file, and database as runtime-mounted data. This avoids generating or printing CA secrets during an ordinary service start. It also does not launch the optional `pcscd` daemon; PC/SC-backed key deployments must provide that service/socket separately. The image runs as fixed UID/GID `10001:10001`; mounted data must be accessible to that identity.

## Runtime contract

- Entrypoint: `/entrypoint.sh`; default command runs the pinned `step-ca` binary.
- Runtime paths: `/home/step/config/ca.json`, `/home/step/secrets/password`, and other CA data under `/home/step`.
- Mount persistent CA state at `/home/step`; never bake signing keys or passwords into the image.
- TCP port: 9000. Health check uses the step CLI's configured CA URL and root certificate.
- The pinned Nixpkgs step CLI is 0.31.0 and the KMS plugin is 0.17.0; these are independently versioned from step-ca 0.30.2.
