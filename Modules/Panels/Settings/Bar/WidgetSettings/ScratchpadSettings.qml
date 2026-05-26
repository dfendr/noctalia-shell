import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property string valueIcon: widgetData.icon !== undefined ? widgetData.icon : widgetMetadata.icon
  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.icon = valueIcon;
    settings.iconColor = valueIconColor;
    settings.textColor = valueTextColor;
    settingsChanged(settings);
  }

  NComboBox {
    Layout.fillWidth: true
    label: "Icon"
    description: "Glyph displayed when the scratchpad has at least one window."
    minimumWidth: 240
    model: [
      {
        "key": "prompt",
        "name": "Terminal prompt"
      },
      {
        "key": "terminal",
        "name": "Terminal"
      },
      {
        "key": "terminal-2",
        "name": "Terminal (alt)"
      },
      {
        "key": "app-window",
        "name": "App window"
      },
      {
        "key": "app-window-filled",
        "name": "App window (filled)"
      },
      {
        "key": "window",
        "name": "Window"
      },
      {
        "key": "code",
        "name": "Code"
      },
      {
        "key": "box",
        "name": "Box"
      }
    ]
    currentKey: root.valueIcon
    onSelected: key => {
      root.valueIcon = key;
      saveSettings();
    }
    defaultValue: widgetMetadata.icon
  }

  NColorChoice {
    label: I18n.tr("common.select-icon-color")
    currentKey: valueIconColor
    onSelected: key => {
      valueIconColor = key;
      saveSettings();
    }
    defaultValue: widgetMetadata.iconColor
  }

  NColorChoice {
    currentKey: valueTextColor
    onSelected: key => {
      valueTextColor = key;
      saveSettings();
    }
    defaultValue: widgetMetadata.textColor
  }
}
