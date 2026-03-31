{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = builtins.getEnv "USER";
  home.homeDirectory = builtins.getEnv "HOME";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  home.stateVersion = "23.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Development packages
  home.packages = with pkgs; [
    go_1_23  # Go 1.23 (closest available to 1.25)
    nodejs_22  # Node.js 22
    python314  # Python 3.14
  ];

  # Git configuration
  programs.git = {
    enable = true;
    userName = "smol";
    userEmail = "smol@ss.isbuild.ing";
  };
}
