{
  description = "TODO";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, flake-utils }: {
    lib = import ./. { inherit (flake-utils.lib) defaultSystems; };
  };

  # TODO: tests
  # TODO: examples
  # TODO: CI
}
