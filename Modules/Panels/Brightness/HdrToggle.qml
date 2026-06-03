import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Per-monitor HDR toggle pill for the Display panel's monitor cards.
//
// Reuses the shared hypr scripts (chezmoi-deployed to every host) rather
// than re-implementing the hyprctl dance:
//   ~/.local/bin/hypr/hdr <output>                  flips cm hdr<->srgb via hyprctl eval
//   ~/.config/waybar/scripts/hdr-state.sh <output>  emits {class,tooltip} JSON
// State is polled every 2s; a toggle re-polls immediately on completion.
// Border/label colour reflect state: primary=HDR on, neutral=SDR, error=stale.
Rectangle {
  id: root

  required property string screenName

  property string statusClass: "stale"
  property string tooltip: ""

  implicitWidth: label.implicitWidth + Style.marginM * 2
  implicitHeight: Math.round(Style.baseWidgetSize * 0.62)
  radius: height / 2

  color: ma.containsMouse ? Color.mSurfaceVariant : "transparent"
  border.width: Style.borderS
  border.color: {
    if (root.statusClass === "active")
      return Color.mPrimary;
    if (root.statusClass === "stale")
      return Color.mError;
    return ma.containsMouse ? Color.mOnSurfaceVariant : Color.mOutline;
  }

  Behavior on color {
    enabled: root.visible && !Color.isTransitioning
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.InOutQuad
    }
  }
  Behavior on border.color {
    enabled: root.visible && !Color.isTransitioning
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.InOutQuad
    }
  }

  NText {
    id: label
    anchors.centerIn: parent
    text: "HDR"
    pointSize: Style.fontSizeXS
    font.weight: Style.fontWeightBold
    color: {
      if (root.statusClass === "active")
        return Color.mPrimary;
      return ma.containsMouse ? Color.mOnSurface : Color.mOnSurfaceVariant;
    }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.tooltip)
      TooltipService.show(root, root.tooltip, "auto")
    onExited: TooltipService.hide(root)
    onClicked: {
      TooltipService.hide(root);
      toggleProc.command = [Quickshell.env("HOME") + "/.local/bin/hypr/hdr", root.screenName];
      toggleProc.running = true;
    }
  }

  Process {
    id: poll
    command: ["bash", Quickshell.env("HOME") + "/.config/waybar/scripts/hdr-state.sh", root.screenName]
    running: false
    stdout: StdioCollector {
      id: out
      onTextChanged: {
        try {
          const j = JSON.parse(out.text);
          root.statusClass = j.class || "stale";
          root.tooltip = j.tooltip || "";
        } catch (e) {
          // partial reads — ignore until next poll
        }
      }
    }
  }

  Process {
    id: toggleProc
    onRunningChanged: if (!running)
      poll.running = true
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: poll.running = true
  }
}
