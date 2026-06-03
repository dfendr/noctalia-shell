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
  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property string valueMiddleClickCommand: widgetData.middleClickCommand !== undefined ? widgetData.middleClickCommand : widgetMetadata.middleClickCommand
  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor
  // Downstream fork: click behavior — "panel" (default, opens audio panel
  // like Volume) or "mute" (toggles input mute).
  property string valueClickAction: widgetData.clickAction !== undefined ? widgetData.clickAction : (widgetMetadata.clickAction || "panel")

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.displayMode = valueDisplayMode;
    settings.middleClickCommand = valueMiddleClickCommand;
    settings.iconColor = valueIconColor;
    settings.textColor = valueTextColor;
    settings.clickAction = valueClickAction;
    settingsChanged(settings);
  }

  NComboBox {
    label: I18n.tr("common.display-mode")
    description: I18n.tr("bar.volume.display-mode-description")
    minimumWidth: 200
    model: [
      {
        "key": "onhover",
        "name": I18n.tr("display-modes.on-hover")
      },
      {
        "key": "alwaysShow",
        "name": I18n.tr("display-modes.always-show")
      },
      {
        "key": "alwaysHide",
        "name": I18n.tr("display-modes.always-hide")
      }
    ]
    currentKey: valueDisplayMode
    onSelected: key => {
                  valueDisplayMode = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.displayMode
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

  // Downstream fork: click action selector.
  NComboBox {
    label: "Left click"
    description: "Open the audio panel like the Volume widget, or toggle input mute for one-click mic kill."
    minimumWidth: 200
    model: [
      { "key": "panel", "name": "Open audio panel" },
      { "key": "mute",  "name": "Toggle mic mute" }
    ]
    currentKey: valueClickAction
    onSelected: key => {
                  valueClickAction = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.clickAction || "panel"
  }

  // Middle click command
  NTextInput {
    label: I18n.tr("bar.custom-button.middle-click-label")
    description: I18n.tr("panels.audio.on-middle-clicked-description")
    placeholderText: I18n.tr("panels.audio.external-mixer-placeholder")
    text: valueMiddleClickCommand
    onTextChanged: {
      valueMiddleClickCommand = text;
      saveSettings();
    }
    defaultValue: widgetMetadata.middleClickCommand
  }
}
