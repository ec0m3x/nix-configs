{
  config,
  pkgs,
  ...
}: {
  sops.secrets.cloudflared_tunnel_token = {};
  sops.templates.cloudflared_env = {
    mode = "0400";
    restartUnits = ["cloudflared-token-tunnel.service"];
    content = ''
      TUNNEL_TOKEN=${config.sops.placeholder.cloudflared_tunnel_token}
    '';
  };

  systemd.services.cloudflared-token-tunnel = {
    description = "Cloudflare remotely-managed tunnel";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      DynamicUser = true;
      EnvironmentFile = config.sops.templates.cloudflared_env.path;
      ExecStart = "${pkgs.unstable.cloudflared}/bin/cloudflared tunnel --no-autoupdate --metrics 127.0.0.1:2000 run";
      Restart = "on-failure";
      RestartSec = "5s";
      StateDirectory = "cloudflared";
    };
  };
}
