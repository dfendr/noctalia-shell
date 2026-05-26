import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.UI
import qs.Widgets

// Per-monitor scratchpad indicator. Three states:
//   • Hidden — no scratchpad windows exist anywhere.
//   • Idle   — scratchpad windows exist but THIS monitor isn't showing them.
//   • Active — THIS monitor currently has the special workspace mapped.
// Click toggles via ~/.local/bin/hypr/scratchpad-term (smart toggle:
// launches ghostty if missing, moves it back to special:term if it has
// drifted to another workspace, otherwise plain toggle).
//
// State is event-driven via Hyprland.rawEvent — idle cost is zero
// processes; a single hyprctl query fires only when an event that could
// change scratchpad state arrives (special-workspace activate, window
// create/destroy/move, workspace create/destroy).
Item {
  id: root

  property ShellScreen screen

  // Standard widget plumbing (matches the other Modules/Bar/Widgets/*).
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId] ?? {}
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
  readonly property string iconKey: widgetSettings.icon !== undefined ? widgetSettings.icon : (widgetMetadata.icon || "prompt")
  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor
  readonly property string textColorKey: widgetSettings.textColor !== undefined ? widgetSettings.textColor : widgetMetadata.textColor

  // State observed from Hyprland.
  property int count: 0
  property bool shownHere: false

  visible: count > 0
  implicitWidth: visible ? pill.width : 0
  implicitHeight: visible ? pill.height : 0

  // ─── Hyprland event subscription ────────────────────────────
  readonly property var _relevantEvents: ({
                                            "activespecial": true,
                                            "activespecialv2": true,
                                            "openwindow": true,
                                            "closewindow": true,
                                            "movewindow": true,
                                            "movewindowv2": true,
                                            "createworkspace": true,
                                            "destroyworkspace": true,
                                            "createworkspacev2": true,
                                            "destroyworkspacev2": true
                                          })

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root._relevantEvents[event.name])
        poll.running = true;
    }
  }

  // ─── Query: read both monitors and clients in one bash pipeline ─
  Process {
    id: poll
    command: ["bash", "-c", "M=\"$MON\"; mon_json=$(hyprctl -j monitors); cli_json=$(hyprctl -j clients); here=$(echo \"$mon_json\" | jq -r --arg m \"$M\" '.[] | select(.name==$m) | .specialWorkspace.name'); count=$(echo \"$cli_json\" | jq '[.[] | select(.workspace.id < 0)] | length'); echo \"$here|$count\""]
    environment: ({
                    "MON": root.screenName
                  })
    stdout: StdioCollector {
      onTextChanged: {
        const parts = text.trim().split("|");
        if (parts.length < 2)
          return;
        root.shownHere = parts[0].length > 0;
        root.count = parseInt(parts[1], 10) || 0;
      }
    }
  }

  // Initial query at startup so the icon reflects current state before any event fires.
  Component.onCompleted: poll.running = true

  // ─── Visual ─────────────────────────────────────────────────
  BarPill {
    id: pill
    screen: root.screen
    icon: root.iconKey
    oppositeDirection: BarService.getPillDirection(root)
    customIconColor: root.shownHere ? Color.mPrimary : Color.resolveColorKeyOptional(root.iconColorKey)
    customTextColor: Color.resolveColorKeyOptional(root.textColorKey)
    tooltipText: root.shownHere ? "Scratchpad on this monitor (click to hide)" : "Scratchpad active (click to show here)"
    onClicked: Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.local/bin/hypr/scratchpad-term"])
  }
}
