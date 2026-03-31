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
  home.stateVersion = "25.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Development packages
  home.packages = with pkgs; [
    go_1_25
    nodejs_22  # Node.js 22
    python314  # Python 3.14
    gh  # GitHub CLI
    jq  # JSON processor
    toml2json  # TOML to JSON converter
  ];

  # Git configuration
  programs.git = {
    enable = true;
    userName = "smol";
    userEmail = "smol@ss.isbuild.ing";
  };

  # gh-pm configuration directory (empty repo settings, can be edited on demand)
  home.file.".gh-pm/gh-pm.toml".text = ''
    [settings]
    repos = []  # Add your repositories here
    poll_interval = 60
    workflow_timeout = 3600
    max_retries = 3
    log_level = "INFO"
    log_file = "~/.gh-pm/gh-pm.log"
    workflow_command = "~/.gh-pm/workflow"

    [profiles.default]
    model = "gpt-4o"
    api_url = "https://api.openai.com/v1"
    api_key_env = "OPENAI_API_KEY"
  '';
}
