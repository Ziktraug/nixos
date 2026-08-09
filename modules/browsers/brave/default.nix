{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.browsers.brave;
  braveMainProgram = pkgs.brave.meta.mainProgram or "brave";
  braveCommandLineArgs = [
    "--force-dark-mode"
    "--enable-features=WebUIDarkMode"
    # Workarounds for NVIDIA/Wayland video/compositor artifacts
    # - Accelerated video decode: repeated NVIDIA Xid/soft-lockup crashes
    # - WaylandWpColorManagerV1: color corruption after dim/wake
    # - UseMultiPlaneFormatForHardwareVideo: intermittent green flashes
    "--disable-accelerated-video-decode"
    "--disable-gpu-memory-buffer-video-frames"
    "--disable-features=WaylandWpColorManagerV1,UseMultiPlaneFormatForHardwareVideo"
    # Proton/WireGuard can make browser HTTP/3/QUIC stalls look like
    # intermittent DNS or connectivity drops while TCP probes stay green.
    "--disable-quic"
  ];
  braveWithFlags = pkgs.symlinkJoin {
    name = "brave-with-flags-${pkgs.brave.version}";
    paths = [ pkgs.brave ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/${braveMainProgram}" ${
        concatMapStringsSep " " (flag: "--add-flag ${escapeShellArg flag}") braveCommandLineArgs
      }
    '';
    meta = pkgs.brave.meta;
  };
in
{
  options.applications.browsers.brave = {
    enable = mkEnableOption "Brave browser";
    dotfiles.enable = mkEnableOption "Brave dotfiles management";
  };

  config = mkIf cfg.enable {
    # Install Brave browser with dark mode
    environment.systemPackages = [ braveWithFlags ];

    # Configure extensions and policies using programs.chromium (which supports Brave)
    programs.chromium = {
      enable = true;
      extensions = [
        # "khncfooichmfjbepaaaebmommgaepoid" # Youtube Unhook
        "mnjggcdmjocbbbhaepdhchncahnbgone" # YouTube SponsorBlock
        "kpmjjdhbcfebfjgdnpjagcndoelnidfj" # Twitter Control Panel
        "ghmbeldphafepmbegfdlkpapadhbakde" # Proton Pass
        "eimadpbcbfnmbkopoojfekhnkhdbieeh" # Dark Reader
        "enamippconapkdmgfgjchkhakpfinmaj" # DeArrow
        "bkkmolkhemgaeaeggcmfbghljjjoofoh" # Catppuccin Mocha theme
      ];

      # Brave policies for crypto/web3 removal, privacy, and security
      extraOpts = {
        BraveRewardsDisabled = true;
        BraveWalletDisabled = true;
        BraveVPNDisabled = true;
        BraveAIChatEnabled = false;
        BraveTorDisabled = true;
        BraveNewsEnabled = false;
        BraveShieldsEnabledForUrls = [ "*" ];
        BraveAdBlockEnabled = true;
        BraveFingerprintingBlockEnabled = true;
        BraveHTTPSUpgradeEnabled = true;
        DnsOverHttpsMode = "off";
        DefaultWebBluetoothGuardSetting = 2;
        DefaultWebUsbGuardSetting = 2;
        DefaultSerialGuardSetting = 2;
        DefaultGeolocationSetting = 2;
        DefaultNotificationsSetting = 2;
        DefaultSensorsSetting = 2;
        DefaultInsecureContentSetting = 2;
        DefaultFileSystemReadGuardSetting = 2;
        DefaultFileSystemWriteGuardSetting = 2;
        DefaultWebHidGuardSetting = 2;
        DefaultLocalFontsGuardSetting = 2;
        DefaultWindowManagementGuardSetting = 2;
        AutofillAddressEnabled = false;
        AutofillCreditCardEnabled = false;
        PasswordManagerEnabled = false;
        PaymentMethodQueryEnabled = false;
        MetricsReportingEnabled = false;
        SpellcheckEnabled = true;
        SafeBrowsingEnabled = true;
        SafeBrowsingExtendedReportingEnabled = false;
        SearchSuggestEnabled = false;
        AlternateErrorPagesEnabled = false;
        NetworkPredictionOptions = 2;
        DefaultCookiesSetting = 1;
        DefaultJavaScriptSetting = 1;
        DefaultImagesSetting = 1;
        DefaultPluginsSetting = 3;
        DefaultPopupsSetting = 2;
        SyncDisabled = true;
        SigninAllowed = false;
        BrowserSignin = 0;
        CloudPrintSubmitEnabled = false;
        EnableMediaRouter = false;
        AudioCaptureAllowed = false;
        VideoCaptureAllowed = false;
        SSLErrorOverrideAllowed = false;
        AdvancedProtectionAllowed = false;
        RemoteAccessHostFirewallTraversal = false;
        BackgroundModeEnabled = false;
        # Avoid NVIDIA/Wayland GPU hangs in Brave renderer/video paths.
        HardwareAccelerationModeEnabled = false;
        TranslateEnabled = false;
        BookmarkBarEnabled = true;
        ShowHomeButton = true;
        HomepageIsNewTabPage = true;
        DefaultSearchProviderEnabled = true;
        DefaultSearchProviderName = "DuckDuckGo";
        DefaultSearchProviderKeyword = "ddg";
        DefaultSearchProviderSearchURL = "https://duckduckgo.com/?q={searchTerms}";
        DefaultSearchProviderSuggestURL = "https://ac.duckduckgo.com/ac/?q={searchTerms}&type=list";
        PrivacySandboxAdTopicsEnabled = false;
        PrivacySandboxAdMeasurementEnabled = false;
        PrivacySandboxPromptEnabled = false;
        HttpsOnlyMode = "force_enabled";
        HighEfficiencyModeEnabled = true;
        BatterySaverModeAvailability = 1;
        SharedClipboardEnabled = false;
        UrlKeyedAnonymizedDataCollectionEnabled = false;
        UserFeedbackAllowed = false;
        ChromeCleanupEnabled = false;
        ChromeCleanupReportingEnabled = false;
        EnableOnlineRevocationChecks = true;
        RequireOnlineRevocationChecksForLocalAnchors = true;
        BlockThirdPartyCookies = true;
        DefaultThirdPartyCookiesSetting = 2;

        # Force dark theme in Brave appearance settings
        # 0 = Default/System, 1 = Light, 2 = Dark
        BraveTheme = 2;
      };
    };

    # Dotfiles management
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.brave = {
        enable = true;
        sourceDir = "modules/browsers/brave";
        mappings = {
          policies = {
            source = "policies.json";
            target = "$HOME/.config/BraveSoftware/Brave-Browser/Policies/Managed/GroupPolicy.json";
          };
        };
      };
    };
  };
}
