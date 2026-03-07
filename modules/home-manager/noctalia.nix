{ config, lib, pkgs, inputs, ... }:
let
  # Monitor configuration - adjust this to match your display
  primaryMonitor = "DP-2";

  # Noctalia settings configuration
  noctaliaSettings = {
    appLauncher = {
      autoPasteClipboard = false;
      clipboardWatchImageCommand = "wl-paste --type image --watch cliphist store";
      clipboardWatchTextCommand = "wl-paste --type text --watch cliphist store";
      clipboardWrapText = true;
      customLaunchPrefix = "";
      customLaunchPrefixEnabled = false;
      density = "default";
      enableClipPreview = true;
      enableClipboardHistory = true;
      enableSessionSearch = true;
      enableSettingsSearch = true;
      enableWindowsSearch = true;
      iconMode = "tabler";
      ignoreMouseInput = false;
      overviewLayer = false;
      pinnedApps = [];
      position = "center";
      screenshotAnnotationTool = "";
      showCategories = true;
      showIconBackground = false;
      sortByMostUsed = true;
      terminalCommand = "kitty";
      useApp2Unit = false;
      viewMode = "list";
    };

    audio = {
      mprisBlacklist = [];
      preferredPlayer = "";
      spectrumFrameRate = 30;
      visualizerType = "linear";
      volumeFeedback = false;
      volumeFeedbackSoundFile = "";
      volumeOverdrive = false;
      volumeStep = 5;
    };

    bar = {
      autoHideDelay = 500;
      autoShowDelay = 150;
      backgroundOpacity = 0.93;
      barType = "simple";
      capsuleColorKey = "none";
      capsuleOpacity = 1;
      contentPadding = 2;
      density = "default";
      displayMode = "always_visible";
      floating = false;
      fontScale = 1;
      frameRadius = 12;
      frameThickness = 8;
      hideOnOverview = false;
      marginHorizontal = 4;
      marginVertical = 4;
      middleClickAction = "none";
      middleClickCommand = "";
      middleClickFollowMouse = false;
      monitors = [ primaryMonitor ];  # Configure for primary monitor
      mouseWheelAction = "none";
      mouseWheelWrap = true;
      outerCorners = true;
      position = "top";
      reverseScroll = false;
      rightClickAction = "controlCenter";
      rightClickCommand = "";
      rightClickFollowMouse = true;
      screenOverrides = [];
      showCapsule = true;
      showOnWorkspaceSwitch = true;
      showOutline = false;
      useSeparateOpacity = false;
      widgetSpacing = 6;
      widgets = {
        center = [
          { id = "Clock"; }
        ];
        left = [
          { id = "Launcher"; }
          { id = "Workspace"; }
          { id = "SystemMonitor"; }
          { id = "ActiveWindow"; }
          { id = "MediaMini"; }
        ];
        right = [
          { id = "Tray"; }
          { id = "NotificationHistory"; }
          { id = "Battery"; }
          { id = "Volume"; }
          { id = "Brightness"; }
          { id = "ControlCenter"; }
        ];
      };
    };

    brightness = {
      backlightDeviceMappings = [];
      brightnessStep = 5;
      enableDdcSupport = false;
      enforceMinimum = true;
    };

    calendar = {
      cards = [
        { enabled = true; id = "calendar-header-card"; }
        { enabled = true; id = "calendar-month-card"; }
        { enabled = true; id = "weather-card"; }
      ];
    };

    colorSchemes = {
      darkMode = true;
      generationMethod = "tonal-spot";
      manualSunrise = "06:30";
      manualSunset = "18:30";
      monitorForColors = "";
      predefinedScheme = "Noctalia (default)";
      schedulingMode = "off";
      useWallpaperColors = true;
    };

    controlCenter = {
      cards = [
        { enabled = true; id = "profile-card"; }
        { enabled = true; id = "shortcuts-card"; }
        { enabled = true; id = "audio-card"; }
        { enabled = false; id = "brightness-card"; }
        { enabled = true; id = "weather-card"; }
        { enabled = true; id = "media-sysmon-card"; }
      ];
      diskPath = "/";
      position = "close_to_bar_button";
      shortcuts = {
        left = [
          { id = "Network"; }
          { id = "Bluetooth"; }
          { id = "WallpaperSelector"; }
          { id = "NoctaliaPerformance"; }
        ];
        right = [
          { id = "Notifications"; }
          { id = "PowerProfile"; }
          { id = "KeepAwake"; }
          { id = "NightLight"; }
        ];
      };
    };

    desktopWidgets = {
      enabled = false;
      gridSnap = false;
      monitorWidgets = [];
      overviewEnabled = true;
    };

    dock = {
      animationSpeed = 1;
      backgroundOpacity = 1;
      colorizeIcons = false;
      deadOpacity = 0.6;
      displayMode = "auto_hide";
      dockType = "floating";
      enabled = true;
      floatingRatio = 1;
      groupApps = false;
      groupClickAction = "cycle";
      groupContextMenuMode = "extended";
      groupIndicatorStyle = "dots";
      inactiveIndicators = false;
      indicatorColor = "primary";
      indicatorOpacity = 0.6;
      indicatorThickness = 3;
      launcherIconColor = "none";
      launcherPosition = "end";
      monitors = [ primaryMonitor ];  # Configure for primary monitor
      onlySameOutput = true;
      pinnedApps = [];
      pinnedStatic = false;
      position = "bottom";
      showDockIndicator = false;
      showLauncherIcon = false;
      sitOnFrame = false;
      size = 1;
    };

    general = {
      allowPanelsOnScreenWithoutBar = true;
      allowPasswordWithFprintd = false;
      animationDisabled = false;
      animationSpeed = 1;
      autoStartAuth = false;
      avatarImage = "${config.home.homeDirectory}/.face";
      boxRadiusRatio = 1;
      clockFormat = "hh\\nmm";
      clockStyle = "custom";
      compactLockScreen = false;
      dimmerOpacity = 0.2;
      enableBlurBehind = true;
      enableLockScreenCountdown = true;
      enableLockScreenMediaControls = false;
      enableShadows = true;
      forceBlackScreenCorners = false;
      iRadiusRatio = 1;
      keybinds = {
        keyDown = [ "Down" ];
        keyEnter = [ "Return" "Enter" ];
        keyEscape = [ "Esc" ];
        keyLeft = [ "Left" ];
        keyRemove = [ "Del" ];
        keyRight = [ "Right" ];
        keyUp = [ "Up" ];
      };
      language = "";
      lockOnSuspend = true;
      lockScreenAnimations = false;
      lockScreenBlur = 0;
      lockScreenCountdownDuration = 10000;
      lockScreenMonitors = [];
      lockScreenTint = 0;
      passwordChars = false;
      radiusRatio = 1;
      reverseScroll = false;
      scaleRatio = 1;
      screenRadiusRatio = 1;
      shadowDirection = "bottom_right";
      shadowOffsetX = 2;
      shadowOffsetY = 3;
      showChangelogOnStartup = false;
      showHibernateOnLockScreen = false;
      showScreenCorners = false;
      showSessionButtonsOnLockScreen = true;
      telemetryEnabled = false;
    };

    hooks = {
      darkModeChange = "";
      enabled = false;
      performanceModeDisabled = "";
      performanceModeEnabled = "";
      screenLock = "";
      screenUnlock = "";
      session = "";
      startup = "";
      wallpaperChange = "";
    };

    idle = {
      customCommands = "[]";
      enabled = false;
      fadeDuration = 5;
      lockCommand = "";
      lockTimeout = 660;
      resumeLockCommand = "";
      resumeScreenOffCommand = "";
      resumeSuspendCommand = "";
      screenOffCommand = "";
      screenOffTimeout = 600;
      suspendCommand = "";
      suspendTimeout = 1800;
    };

    location = {
      analogClockInCalendar = false;
      firstDayOfWeek = -1;
      hideWeatherCityName = false;
      hideWeatherTimezone = false;
      name = "Weikersheim";
      showCalendarEvents = true;
      showCalendarWeather = true;
      showWeekNumberInCalendar = false;
      use12hourFormat = false;
      useFahrenheit = false;
      weatherEnabled = true;
      weatherShowEffects = true;
    };

    network = {
      airplaneModeEnabled = false;
      bluetoothAutoConnect = true;
      bluetoothDetailsViewMode = "grid";
      bluetoothHideUnnamedDevices = false;
      bluetoothRssiPollIntervalMs = 60000;
      bluetoothRssiPollingEnabled = false;
      disableDiscoverability = false;
      networkPanelView = "wifi";
      wifiDetailsViewMode = "grid";
      wifiEnabled = true;
    };

    nightLight = {
      autoSchedule = true;
      dayTemp = "6500";
      enabled = false;
      forced = false;
      manualSunrise = "06:30";
      manualSunset = "18:30";
      nightTemp = "4000";
    };

    noctaliaPerformance = {
      disableDesktopWidgets = true;
      disableWallpaper = true;
    };

    notifications = {
      backgroundOpacity = 1;
      clearDismissed = true;
      criticalUrgencyDuration = 15;
      density = "default";
      enableBatteryToast = true;
      enableKeyboardLayoutToast = true;
      enableMarkdown = false;
      enableMediaToast = false;
      enabled = true;
      location = "top_right";
      lowUrgencyDuration = 3;
      monitors = [];
      normalUrgencyDuration = 8;
      overlayLayer = true;
      respectExpireTimeout = false;
      saveToHistory = {
        critical = true;
        low = true;
        normal = true;
      };
      sounds = {
        criticalSoundFile = "";
        enabled = false;
        excludedApps = "discord,zen-browser,chrome,chromium,edge";
        lowSoundFile = "";
        normalSoundFile = "";
        separateSounds = false;
        volume = 0.5;
      };
    };

    osd = {
      autoHideMs = 2000;
      backgroundOpacity = 1;
      enabled = true;
      enabledTypes = [ 0 1 2 ];
      location = "top_right";
      monitors = [];
      overlayLayer = true;
    };

    plugins = {
      autoUpdate = false;
    };

    sessionMenu = {
      countdownDuration = 10000;
      enableCountdown = true;
      largeButtonsLayout = "single-row";
      largeButtonsStyle = true;
      position = "center";
      powerOptions = [
        { action = "lock"; enabled = true; keybind = "1"; }
        { action = "suspend"; enabled = true; keybind = "2"; }
        { action = "hibernate"; enabled = true; keybind = "3"; }
        { action = "reboot"; enabled = true; keybind = "4"; }
        { action = "logout"; enabled = true; keybind = "5"; }
        { action = "shutdown"; enabled = true; keybind = "6"; }
        { action = "rebootToUefi"; enabled = true; keybind = "7"; }
      ];
      showHeader = true;
      showKeybinds = false;
    };

    settingsVersion = 0;

    systemMonitor = {
      batteryCriticalThreshold = 5;
      batteryWarningThreshold = 20;
      cpuCriticalThreshold = 90;
      cpuWarningThreshold = 80;
      criticalColor = "";
      diskAvailCriticalThreshold = 10;
      diskAvailWarningThreshold = 20;
      diskCriticalThreshold = 90;
      diskWarningThreshold = 80;
      enableDgpuMonitoring = false;
      externalMonitor = "resources || missioncenter || jdsystemmonitor || corestats || system-monitoring-center || gnome-system-monitor || plasma-systemmonitor || mate-system-monitor || ukui-system-monitor || deepin-system-monitor || pantheon-system-monitor";
      gpuCriticalThreshold = 90;
      gpuWarningThreshold = 80;
      memCriticalThreshold = 90;
      memWarningThreshold = 80;
      swapCriticalThreshold = 90;
      swapWarningThreshold = 80;
      tempCriticalThreshold = 90;
      tempWarningThreshold = 80;
      useCustomColors = false;
      warningColor = "";
    };

    templates = {
      activeTemplates = [];
      enableUserTheming = false;
    };

    ui = {
      boxBorderEnabled = false;
      fontDefault = "Sans Serif";
      fontDefaultScale = 1;
      fontFixed = "monospace";
      fontFixedScale = 1;
      panelBackgroundOpacity = 0.93;
      panelsAttachedToBar = true;
      settingsPanelMode = "attached";
      settingsPanelSideBarCardStyle = false;
      tooltipsEnabled = true;
    };

    wallpaper = {
      automationEnabled = false;
      directory = "/home/ecomex/Code/nix-configs/wallpapers";
      enableMultiMonitorDirectories = false;
      enabled = true;
      favorites = [];
      fillColor = "#000000";
      fillMode = "crop";
      hideWallpaperFilenames = false;
      monitorDirectories = [];
      overviewBlur = 0.4;
      overviewEnabled = false;
      overviewTint = 0.6;
      panelPosition = "follow_bar";
      randomIntervalSec = 300;
      setWallpaperOnAllMonitors = true;
      showHiddenFiles = false;
      skipStartupTransition = false;
      solidColor = "#1a1a2e";
      sortOrder = "name";
      transitionDuration = 1500;
      transitionEdgeSmoothness = 0.05;
      transitionType = "random";
      useSolidColor = false;
      useWallhaven = false;
      viewMode = "single";
      wallhavenApiKey = "";
      wallhavenCategories = "111";
      wallhavenOrder = "desc";
      wallhavenPurity = "100";
      wallhavenQuery = "";
      wallhavenRatios = "";
      wallhavenResolutionHeight = "";
      wallhavenResolutionMode = "atleast";
      wallhavenResolutionWidth = "";
      wallhavenSorting = "relevance";
      wallpaperChangeMode = "random";
    };
  };

  # Plugins configuration
  noctaliaPlugins = {
    version = 2;
    states = {};
    sources = [];
  };

in
{
  # Noctalia - A beautiful, minimal desktop shell for Wayland
  # https://github.com/noctalia-dev/noctalia-shell
  # https://noctalia.dev/

  # Noctalia uses Quickshell (Qt/QML) and works with Niri, Hyprland, Sway, and other Wayland compositors
  # Configuration is managed declaratively through home-manager

  # Install noctalia-shell from flake input and required dependencies
  home.packages = [
    inputs.noctalia.packages.${pkgs.system}.default
  ] ++ (with pkgs; [
    # Qt/QML runtime for Quickshell
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtwayland

    # Noctalia-specific tools
    cliphist  # Clipboard history manager for app launcher
    # Note: pamixer, brightnessctl, playerctl, libnotify are provided by niri module
  ]);

  # Declaratively manage Noctalia configuration
  xdg.configFile."noctalia/settings.json" = {
    text = builtins.toJSON noctaliaSettings;
  };

  xdg.configFile."noctalia/plugins.json" = {
    text = builtins.toJSON noctaliaPlugins;
  };

  # Note: XDG portal configuration is managed by niri module

  # Set environment variables for Qt on Wayland
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  };
}
