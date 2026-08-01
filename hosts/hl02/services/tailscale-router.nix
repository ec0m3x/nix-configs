{...}: {
  # Der gesicherte tailscaled-State behält die bestehende Node-Identität.
  # Das Flag stellt die gewünschte Route zusätzlich deklarativ sicher.
  services.tailscale.extraSetFlags = [
    "--advertise-routes=10.20.50.0/24"
  ];
}
