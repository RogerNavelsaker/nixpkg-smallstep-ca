{
  description = "Smallstep step-ca OCI image built with Nix dockerTools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      stepCa = pkgs.step-ca;
      stepCli = pkgs.step-cli;
      kmsPlugin = pkgs.step-kms-plugin;
      version = "0.30.2";
      fakeNss = pkgs.dockerTools.fakeNss.override {
        extraPasswdLines = [ "step:x:10001:10001:Smallstep CA:/home/step:/noshell" ];
        extraGroupLines = [ "step:x:10001:" ];
      };
      healthcheck = pkgs.writeShellScriptBin "step-ca-healthcheck" ''
        output=$(${stepCli}/bin/step ca health 2>/dev/null) || exit 1
        [ "$output" = "ok" ]
      '';
      entrypoint = pkgs.writeShellScriptBin "step-ca-entrypoint" ''
        exec "$@"
      '';
      runtimeCheck = pkgs.runCommand "step-ca-runtime-contract" {
        nativeBuildInputs = [ pkgs.gnugrep ];
      } ''
        ${stepCa}/bin/step-ca --version 2>&1 | grep -F "${version}"
        ${stepCli}/bin/step version 2>&1 | grep -F "${stepCli.version}"
        test -x ${kmsPlugin}/bin/step-kms-plugin
        test -x ${entrypoint}/bin/step-ca-entrypoint
        test -x ${healthcheck}/bin/step-ca-healthcheck
        grep -F "step:x:10001:10001:" ${fakeNss}/etc/passwd
        grep -F "step:x:10001:" ${fakeNss}/etc/group
        touch "$out"
      '';
      image = assert stepCa.version == version;
        pkgs.dockerTools.buildLayeredImage {
          name = "smallstep-ca";
          tag = version;
          contents = [
            stepCa
            stepCli
            kmsPlugin
            entrypoint
            healthcheck
            fakeNss
            pkgs.cacert
            pkgs.tzdata
          ];

          config = {
            User = "10001:10001";
            WorkingDir = "/home/step";
            Entrypoint = [ "/entrypoint.sh" ];
            Cmd = [
              "${stepCa}/bin/step-ca"
              "--password-file"
              "/home/step/secrets/password"
              "/home/step/config/ca.json"
            ];
            Env = [
              "HOME=/home/step"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "STEPPATH=/home/step"
              "CONFIGPATH=/home/step/config/ca.json"
              "PWDPATH=/home/step/secrets/password"
              "PATH=${stepCa}/bin:${stepCli}/bin:${kmsPlugin}/bin"
              "TZDIR=${pkgs.tzdata}/share/zoneinfo"
            ];
            ExposedPorts = { "9000/tcp" = { }; };
            Volumes = { "/home/step" = { }; };
            StopSignal = "SIGTERM";
            Healthcheck = {
              Test = [ "CMD" "${healthcheck}/bin/step-ca-healthcheck" ];
              Interval = 30000000000;
              Timeout = 5000000000;
              StartPeriod = 30000000000;
              Retries = 3;
            };
            Labels = {
              "org.opencontainers.image.title" = "Smallstep step-ca";
              "org.opencontainers.image.version" = version;
              "org.opencontainers.image.licenses" = "Apache-2.0";
              "org.opencontainers.image.source" = "https://github.com/smallstep/certificates";
              "org.opencontainers.image.description" = "Nix-built Smallstep Certificate Authority image";
            };
          };

          fakeRootCommands = ''
            mkdir -p ./home/step/config ./home/step/secrets ./home/step/certs ./home/step/db
            ln -sfn ${entrypoint}/bin/step-ca-entrypoint ./entrypoint.sh
            chown -R 10001:10001 ./home/step
            chmod 0750 ./home/step ./home/step/config ./home/step/secrets ./home/step/certs ./home/step/db
          '';
        };
    in {
      packages.${system} = {
        step = stepCli;
        inherit image;
        default = image;
      };
      checks.${system} = {
        inherit image;
        runtime-contract = runtimeCheck;
      };
    };
}
