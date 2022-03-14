{ flake  ? builtins.getFlake (toString ./.)
, pkgs ? flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem}
, makeTest ? pkgs.callPackage (flake.inputs.nixpkgs + "/nixos/tests/make-test-python.nix")
, package ? flake.defaultPackage.${builtins.currentSystem}
}:

makeTest {
  name = "hive";
  nodes.machine = {...}: {
		imports = [flake.nixosModule];
		services.hiveserver.enable = true;
	};

  testScript = ''
start_all()
machine.wait_for_unit("hiveserver.service")
# machine.succeed(
# "echo \"hello\"; echo \"how are you\";beeline -u jdbc:hive2://machine:10000 -e \"SHOW TABLES\""
#     )
  '';
} {
  inherit pkgs;
  inherit (pkgs) system;
}
