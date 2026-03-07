### ComfyUI in a nix shell FHS environment
### This is a shell.nix file that creates a FHS environment for ComfyUI

# Installation:
# Clone the comfyui repository
# Run: 
# - nix-shell shell.nix
# - python -m venv venv
# - source venv/bin/activate
# - pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124
# - pip install -r requirements.txt
# - start-comfy
###


{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

(pkgs.buildFHSEnv {
  name = "comfyui-env";
  targetPkgs = pkgs: (with pkgs; [
    python312
    python312Packages.pip
    python312Packages.virtualenv
    git
    git-lfs
    libGL
    libGLU
    stdenv.cc.cc.lib
    glib
    xorg.libX11
    xorg.libXi
    xorg.libXext
    xorg.libXrender
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXrandr
    xorg.libXft
    cudaPackages.cudatoolkit
    linuxPackages.nvidia_x11
  ]);

  runScript = pkgs.writeScript "init.sh" ''
    # We define a function instead of an alias, this is more stable in sub-shells
    cat <<EOF > /tmp/comfy_bashrc
    [ -f ~/.bashrc ] && . ~/.bashrc

    start-comfy() {
      echo "Trying to activate venv..."
      if [ -f "venv/bin/activate" ]; then
        source venv/bin/activate
        echo "Venv active. Starting Python..."
        # We don't use exec, so the shell stays open if Python crashes
        python main.py --listen 0.0.0.0 --enable-manager --highvram --preview-method auto
      else
        echo "ERROR: venv/bin/activate not found!"
        echo "Are you in the correct directory? (/home/ecomex/ComfyUI)"
      fi
    }

    echo "-------------------------------------------------------"
    echo " 🚀 ComfyUI FHS environment ready!"
    echo " Type 'start-comfy' to start."
    echo "-------------------------------------------------------"
EOF

    exec bash --rcfile /tmp/comfy_bashrc
  '';
}).env