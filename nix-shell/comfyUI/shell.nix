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
    # Wir definieren eine Funktion statt eines Alias, das ist in Sub-Shells stabiler
    cat <<EOF > /tmp/comfy_bashrc
    [ -f ~/.bashrc ] && . ~/.bashrc
    
    start-comfy() {
      echo "Versuche venv zu aktivieren..."
      if [ -f "venv/bin/activate" ]; then
        source venv/bin/activate
        echo "Venv aktiv. Starte Python..."
        # Wir nutzen exec nicht, damit die Shell offen bleibt, falls Python crasht
        python main.py --listen 0.0.0.0 --enable-manager --highvram --preview-method auto
      else
        echo "FEHLER: venv/bin/activate nicht gefunden!"
        echo "Bist du im richtigen Verzeichnis? (/home/ecomex/ComfyUI)"
      fi
    }

    echo "-------------------------------------------------------"
    echo " 🚀 ComfyUI FHS-Umgebung bereit!"
    echo " Tippe 'start-comfy' zum Starten."
    echo "-------------------------------------------------------"
EOF

    exec bash --rcfile /tmp/comfy_bashrc
  '';
}).env