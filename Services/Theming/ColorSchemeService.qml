pragma Singleton
import Qt.labs.folderlistmodel

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Theming
import qs.Services.UI

Singleton {
  id: root

  property var schemes: []
  property bool scanning: false
  // Downstream fork: the scheme library is sourced from themectl's themes
  // dir instead of noctalia's bundled Assets/ColorScheme. Each theme lives
  // at <themesDirectory>/<slug>/palette.json with a sibling metadata.json
  // (defaultMode + displayName). themectl applies the same palette to
  // ghostty/hypr/walker/btop/alacritty/firefox, so anything in the noctalia
  // UI is in lockstep with the rest of the desktop.
  property string schemesDirectory: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/themes"
  property string downloadedSchemesDirectory: schemesDirectory
  property string colorsJsonFilePath: Settings.configDir + "colors.json"
  // Last successfully parsed predefined scheme JSON (full object). Used to refresh app templates
  // on wallpaper changes without re-running applyScheme (avoids rewriting colors.json when unchanged).
  property var lastPredefinedSchemeData: null
  readonly property string gtkRefreshScript: Quickshell.shellDir + "/Scripts/python/src/theming/gtk-refresh.py"

  // prefer-light/prefer-dark only; GTK template post_hook still runs full gtk-refresh.
  function pushSystemColorScheme() {
    if (!Settings.data.colorSchemes.syncGsettings)
      return;
    if (TemplateProcessor.isTemplateEnabled("gtk"))
      return;
    const mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
    Quickshell.execDetached(["python3", gtkRefreshScript, "--appearance-only", mode]);
  }

  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      Logger.d("ColorScheme", "Detected dark mode change");
      if (!Settings.data.colorSchemes.useWallpaperColors && Settings.data.colorSchemes.predefinedScheme) {
        // Re-apply current scheme to pick the right variant
        applyScheme(Settings.data.colorSchemes.predefinedScheme);
        // Downstream fork: also propagate the mode flip to themectl so
        // ghostty/hypr/walker/btop/alacritty/firefox follow noctalia's
        // day/night transition.
        root._runThemectl(Settings.data.colorSchemes.predefinedScheme);
      }
      root.pushSystemColorScheme();
      // Toast: dark/light mode switched
      const enabled = !!Settings.data.colorSchemes.darkMode;
      const label = enabled ? I18n.tr("tooltips.switch-to-dark-mode") : I18n.tr("tooltips.switch-to-light-mode");
      const description = I18n.tr("common.enabled");
      ToastService.showNotice(label, description, "dark-mode");
    }
  }

  // --------------------------------
  function init() {
    // does nothing but ensure the singleton is created
    // do not remove
    Logger.i("ColorScheme", "Service started");
    loadColorSchemes();
  }

  function loadColorSchemes() {
    Logger.d("ColorScheme", "Load colorScheme");
    scanning = true;
    schemes = [];
    Quickshell.execDetached(["mkdir", "-p", schemesDirectory]);
    // Downstream fork: scan themectl's themes dir. Each theme is
    // <slug>/palette.json — slug is the canonical identifier.
    findProcess.command = ["find", "-L", schemesDirectory, "-mindepth", "2", "-maxdepth", "2", "-name", "palette.json", "-type", "f"];
    findProcess.running = true;
  }

  // Downstream: returns the slug (parent dir name) for a path or pass-through
  // if already a bare slug. The "basename" terminology here is historical —
  // since every file is palette.json the slug lives in the parent dir.
  function getBasename(path) {
    if (!path)
      return "";
    if (path.indexOf("/") === -1) {
      // Already a slug; keep as-is
      return path;
    }
    var chunks = path.split("/");
    // path = ".../themes/<slug>/palette.json"; slug is the second-to-last segment
    if (chunks.length >= 2) {
      return chunks[chunks.length - 2];
    }
    return chunks[chunks.length - 1].replace(".json", "");
  }

  // Downstream: pretty UI label from a slug — "rose-pine-dawn" → "Rose Pine Dawn".
  function getDisplayName(slugOrPath) {
    var slug = getBasename(slugOrPath);
    if (!slug)
      return "";
    return slug.split("-").map(function (part) {
                                return part.charAt(0).toUpperCase() + part.slice(1);
                              }).join(" ");
  }

  function resolveSchemePath(nameOrPath) {
    if (!nameOrPath)
      return "";
    if (nameOrPath.indexOf("/") !== -1) {
      return nameOrPath;
    }
    var slug = nameOrPath.replace(".json", "");
    var canonical = schemesDirectory + "/" + slug + "/palette.json";
    // Prefer an exact match in the scanned schemes list.
    for (var i = 0; i < schemes.length; i++) {
      if (schemes[i] === canonical || schemes[i].indexOf("/" + slug + "/") !== -1) {
        return schemes[i];
      }
    }
    return canonical;
  }

  // Downstream fork: invoke themectl for the given slug with the active
  // dark/light mode. Used by both the user-driven setPredefinedScheme
  // path and the day/night dark-mode-flip Connection below.
  function _runThemectl(slug) {
    if (!slug)
      return;
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
    Quickshell.execDetached(["themectl", "set", slug, "--mode", mode]);
  }

  function applyScheme(nameOrPath) {
    // Force reload by bouncing the path
    var filePath = resolveSchemePath(nameOrPath);
    schemeReader.path = "";
    schemeReader.path = filePath;
  }

  function setPredefinedScheme(schemeName) {
    Logger.i("ColorScheme", "Attempting to set predefined scheme to:", schemeName);

    var resolvedPath = resolveSchemePath(schemeName);
    var basename = getBasename(schemeName);

    // Check if the scheme actually exists in the loaded schemes list
    var schemeExists = false;
    for (var i = 0; i < schemes.length; i++) {
      if (getBasename(schemes[i]) === basename) {
        schemeExists = true;
        break;
      }
    }

    if (schemeExists) {
      Settings.data.colorSchemes.predefinedScheme = basename;
      applyScheme(schemeName);
      ToastService.showNotice(I18n.tr("panels.color-scheme.title"), getDisplayName(basename), "settings-color-scheme");

      // Downstream fork: also re-skin ghostty/hypr/walker/btop/alacritty/
      // firefox via themectl, threading the active dark/light mode through.
      root._runThemectl(basename);
    } else {
      Logger.e("ColorScheme", "Scheme not found:", schemeName);
      ToastService.showError(I18n.tr("panels.color-scheme.title"), `'${basename}' ` + I18n.tr("common.not-found"));
    }
  }

  Process {
    id: findProcess
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        var output = stdout.text.trim();
        var files = output.split('\n').filter(function (line) {
          return line.length > 0;
        });
        files.sort(function (a, b) {
          var nameA = getBasename(a).toLowerCase();
          var nameB = getBasename(b).toLowerCase();
          return nameA.localeCompare(nameB);
        });
        schemes = files;
        scanning = false;
        Logger.d("ColorScheme", "Listed", schemes.length, "schemes");
        // Normalize stored scheme to basename and re-apply if necessary
        var stored = Settings.data.colorSchemes.predefinedScheme;
        if (stored) {
          var basename = getBasename(stored);
          if (basename !== stored) {
            Settings.data.colorSchemes.predefinedScheme = basename;
          }
          if (!Settings.data.colorSchemes.useWallpaperColors) {
            applyScheme(basename);
          }
        }
      } else {
        Logger.e("ColorScheme", "Failed to find color scheme files");
        schemes = [];
        scanning = false;
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Internal loader to read a scheme file
  FileView {
    id: schemeReader
    onLoaded: {
      try {
        var data = JSON.parse(text());
        var variant = data;
        // If scheme provides dark/light variants, pick based on settings
        if (data && (data.dark || data.light)) {
          if (Settings.data.colorSchemes.darkMode) {
            variant = data.dark || data.light;
          } else {
            variant = data.light || data.dark;
          }
        }
        writeColorsToDisk(variant);
        lastPredefinedSchemeData = data;
        Logger.i("ColorScheme", "Applying color scheme:", getBasename(path));

        // Generate templates for predefined color schemes
        if (hasEnabledTemplates() || Settings.data.templates.enableUserTheming) {
          AppThemeService.generateFromPredefinedScheme(data);
        }
      } catch (e) {
        Logger.e("ColorScheme", "Failed to parse scheme JSON:", path, e);
      }
    }
  }

  // Check if any templates are enabled
  function hasEnabledTemplates() {
    const activeTemplates = Settings.data.templates.activeTemplates;
    if (!activeTemplates || activeTemplates.length === 0) {
      return false;
    }
    for (let i = 0; i < activeTemplates.length; i++) {
      if (activeTemplates[i].enabled) {
        return true;
      }
    }
    return false;
  }

  // Writer to colors.json using a JsonAdapter for safety
  FileView {
    id: colorsWriter
    path: colorsJsonFilePath
    printErrors: false
    onSaved:

    // Logger.i("ColorScheme", "Colors saved")
    {}
    JsonAdapter {
      id: out
      property color mPrimary: "#000000"
      property color mOnPrimary: "#000000"
      property color mSecondary: "#000000"
      property color mOnSecondary: "#000000"
      property color mTertiary: "#000000"
      property color mOnTertiary: "#000000"
      property color mError: "#000000"
      property color mOnError: "#000000"
      property color mSurface: "#000000"
      property color mOnSurface: "#000000"
      property color mSurfaceVariant: "#000000"
      property color mOnSurfaceVariant: "#000000"
      property color mOutline: "#000000"
      property color mShadow: "#000000"
      property color mHover: "#000000"
      property color mOnHover: "#000000"
    }
  }

  function writeColorsToDisk(obj) {
    function pick(o, a, b, fallback) {
      return (o && (o[a] || o[b])) || fallback;
    }
    out.mPrimary = pick(obj, "mPrimary", "primary", out.mPrimary);
    out.mOnPrimary = pick(obj, "mOnPrimary", "onPrimary", out.mOnPrimary);
    out.mSecondary = pick(obj, "mSecondary", "secondary", out.mSecondary);
    out.mOnSecondary = pick(obj, "mOnSecondary", "onSecondary", out.mOnSecondary);
    out.mTertiary = pick(obj, "mTertiary", "tertiary", out.mTertiary);
    out.mOnTertiary = pick(obj, "mOnTertiary", "onTertiary", out.mOnTertiary);
    out.mError = pick(obj, "mError", "error", out.mError);
    out.mOnError = pick(obj, "mOnError", "onError", out.mOnError);
    out.mSurface = pick(obj, "mSurface", "surface", out.mSurface);
    out.mOnSurface = pick(obj, "mOnSurface", "onSurface", out.mOnSurface);
    out.mSurfaceVariant = pick(obj, "mSurfaceVariant", "surfaceVariant", out.mSurfaceVariant);
    out.mOnSurfaceVariant = pick(obj, "mOnSurfaceVariant", "onSurfaceVariant", out.mOnSurfaceVariant);
    out.mOutline = pick(obj, "mOutline", "outline", out.mOutline);
    out.mShadow = pick(obj, "mShadow", "shadow", out.mShadow);
    out.mHover = pick(obj, "mHover", "hover", out.mHover);
    out.mOnHover = pick(obj, "mOnHover", "onHover", out.mOnHover);

    // Force a rewrite by updating the path
    colorsWriter.path = "";
    colorsWriter.path = colorsJsonFilePath;
    colorsWriter.writeAdapter();
  }
}
