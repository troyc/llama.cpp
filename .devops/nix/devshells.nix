{ inputs, ... }:

{
  perSystem =
    {
      config,
      lib,
      system,
      pkgsCuda,
      pkgsRocm,
      ...
    }:
    {
      devShells =
        let
          pkgs = import inputs.nixpkgs { inherit system; };
          stdenv = pkgs.stdenv;
          scripts = config.packages.python-scripts;

          cudaRuntimeLibPath = lib.makeLibraryPath (with pkgsCuda.cudaPackages; [
            cuda_cudart
            libcublas
          ]);

          rocmRuntimeLibPath = lib.makeLibraryPath (with pkgsRocm.rocmPackages; [
            clr
            hipblas
            rocblas
          ]);

          runtimeLibPathFor =
            name:
            if name == "cuda" || name == "mpi-cuda" then
              cudaRuntimeLibPath
            else if name == "rocm" then
              rocmRuntimeLibPath
            else
              "";

          # Without this, FindCUDAToolkit links libcuda from the toolkit's stubs/
          # directory and bakes it into RUNPATH, so binaries load the stub instead
          # of the NixOS driver ("CUDA driver is a stub library").
          cudaDriverHookFor =
            name:
            lib.optionalString (name == "cuda" || name == "mpi-cuda") ''
              export CMAKE_LIBRARY_PATH="/run/opengl-driver/lib''${CMAKE_LIBRARY_PATH:+:$CMAKE_LIBRARY_PATH}"
            '';
        in
        lib.pipe (config.packages) [
          (lib.concatMapAttrs (
            name: package:
            let
              runtimeLibPath = runtimeLibPathFor name;
            in
            {
              ${name} = pkgs.mkShell {
                name = "${name}";
                inputsFrom = [ package ];
                packages = [
                  pkgs.python3Packages.huggingface-hub
                ];
                shellHook = ''
                  echo "Entering ${name} devShell"
                  ${lib.optionalString (runtimeLibPath != "") ''
                    export LD_LIBRARY_PATH="${runtimeLibPath}:$LD_LIBRARY_PATH"
                  ''}
                  ${cudaDriverHookFor name}
                '';
              };
              "${name}-extra" =
                if (name == "python-scripts") then
                  null
                else
                  pkgs.mkShell {
                    name = "${name}-extra";
                    inputsFrom = [
                      package
                      scripts
                    ];
                    # Extra packages that *may* be used by some scripts
                    packages = [
                        pkgs.python3Packages.tiktoken
                        pkgs.python3Packages.huggingface-hub
                    ];
                    shellHook = ''
                      echo "Entering ${name} devShell"
                      export LD_LIBRARY_PATH="${lib.getLib stdenv.cc.cc}/lib${
                        lib.optionalString (runtimeLibPath != "") ":${runtimeLibPath}"
                      }:$LD_LIBRARY_PATH"
                      ${cudaDriverHookFor name}
                    '';
                  };
            }
          ))
          (lib.filterAttrs (name: value: value != null))
        ];
    };
}
