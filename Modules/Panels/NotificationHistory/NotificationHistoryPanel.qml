import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Settings
import qs.Services.System
import qs.Services.UI
import qs.Widgets

// Notification History panel
SmartPanel {
  id: root

  preferredWidth: Math.round((Settings.data.notifications.enableMarkdown ? 540 : 440) * Style.uiScaleRatio)
  preferredHeight: Math.round((Settings.data.notifications.enableMarkdown ? 640 : 540) * Style.uiScaleRatio)

  onOpened: {
    NotificationService.updateLastSeenTs();
  }

  panelContent: Rectangle {
    id: panelContent
    color: "transparent"
    focus: true

    // Force focus when opened
    Connections {
      target: root
      function onOpened() {
        panelContent.forceActiveFocus();
      }
    }

    Keys.onPressed: event => {
                      // Tab navigation for categories
                      if (event.key === Qt.Key_Tab) {
                        currentRange = (currentRange + 1) % 4;
                        event.accepted = true;
                        return;
                      }

                      if (event.key === Qt.Key_Backtab) { // Shift+Tab
                        currentRange = (currentRange - 1 + 4) % 4;
                        event.accepted = true;
                        return;
                      }

                      // Navigation Up/Down
                      if (checkKey(event, 'up')) {
                        moveSelection(-1);
                        event.accepted = true;
                        return;
                      }
                      if (checkKey(event, 'down')) {
                        moveSelection(1);
                        event.accepted = true;
                        return;
                      }

                      // Action Navigation Left/Right
                      if (checkKey(event, 'left')) {
                        moveAction(-1);
                        event.accepted = true;
                        return;
                      }
                      if (checkKey(event, 'right')) {
                        moveAction(1);
                        event.accepted = true;
                        return;
                      }

                      // Activation (Enter)
                      if (checkKey(event, 'enter')) {
                        activateSelection();
                        event.accepted = true;
                        return;
                      }

                      // Removal (Delete/Remove)
                      if (checkKey(event, 'remove') || event.key === Qt.Key_Delete) {
                        removeSelection();
                        event.accepted = true;
                        return;
                      }
                    }

    function parseActions(actions) {
      try {
        return JSON.parse(actions || "[]");
      } catch (e) {
        return [];
      }
    }

    function moveSelection(dir) {
      var items = panelContent.groupedItems || [];
      var count = items.length;
      if (count === 0)
        return;

      var newIndex = focusIndex;

      // If no selection yet, start from beginning (or end if up)
      if (focusIndex === -1) {
        newIndex = dir > 0 ? -1 : count;
      }

      newIndex += dir;

      // Bounds check (groupedItems is pre-filtered to currentRange)
      if (newIndex < 0 || newIndex >= count)
        return;

      focusIndex = newIndex;
      actionIndex = -1; // Reset action selection
      scrollToItem(focusIndex);
    }

    function moveAction(dir) {
      if (focusIndex === -1)
        return;
      var g = (panelContent.groupedItems || [])[focusIndex];
      if (!g)
        return;

      var actions = parseActions(g.primary.actionsJson);

      if (actions.length === 0)
        return;

      var newActionIndex = actionIndex + dir;

      // Clamp between -1 (body) and actions.length - 1
      if (newActionIndex < -1)
        newActionIndex = -1;
      if (newActionIndex >= actions.length)
        newActionIndex = actions.length - 1;

      actionIndex = newActionIndex;
    }

    function activateSelection() {
      if (focusIndex === -1)
        return;
      var g = (panelContent.groupedItems || [])[focusIndex];
      if (!g)
        return;

      if (actionIndex >= 0) {
        var actions = parseActions(g.primary.actionsJson);
        if (actionIndex < actions.length) {
          if (NotificationService.invokeAction(g.primary.id, actions[actionIndex].identifier))
            root.close();
        }
        return;
      }

      // Group with multiple members: Enter toggles group expansion.
      if (g.count > 1) {
        if (scrollView.expandedGroupKey === g.groupKey) {
          scrollView.expandedGroupKey = "";
        } else {
          scrollView.expandedGroupKey = g.groupKey;
        }
        return;
      }

      // Single notification: fall back to per-item expand (when text truncated).
      var delegate = notificationColumn.children[focusIndex];
      if (!delegate)
        return;
      if (!(delegate.canExpand || delegate.isExpanded))
        return;

      if (scrollView.expandedId === g.primary.id) {
        scrollView.expandedId = "";
      } else {
        scrollView.expandedId = g.primary.id;
      }
    }

    function removeSelection() {
      if (focusIndex === -1)
        return;
      var g = (panelContent.groupedItems || [])[focusIndex];
      if (!g)
        return;

      // On a grouped card, Delete clears the whole stack — matches the parent
      // trash button. For a single notification, just remove that one.
      if ((g.count || 1) > 1) {
        dismissGroup(g);
      } else {
        NotificationService.removeFromHistory(g.primary.id);
      }
    }

    function scrollToItem(index) {
      // Find the delegate item
      if (index < 0 || index >= notificationColumn.children.length)
        return;

      var item = notificationColumn.children[index];
      if (item && item.visible) {
        // Use the internal flickable from NScrollView for accurate scrolling
        var flickable = scrollView._internalFlickable;
        if (!flickable || !flickable.contentItem)
          return;

        var pos = flickable.contentItem.mapFromItem(item, 0, 0);
        var itemY = pos.y;
        var itemHeight = item.height;

        var currentContentY = flickable.contentY;
        var viewHeight = flickable.height;

        // Check if above visible area
        if (itemY < currentContentY) {
          flickable.contentY = Math.max(0, itemY - Style.marginM);
        } else
          // Check if below visible area
          if (itemY + itemHeight > currentContentY + viewHeight) {
            flickable.contentY = (itemY + itemHeight) - viewHeight + Style.marginM;
          }
      }
    }

    // Calculate content height based on header + tabs (if visible) + content
    property real calculatedHeight: {
      if (NotificationService.historyModel.count === 0) {
        return headerBox.implicitHeight + scrollView.implicitHeight + Style.margin2L + Style.marginM;
      }
      return headerBox.implicitHeight + scrollView.implicitHeight + Style.margin2L + Style.marginM;
    }
    property real contentPreferredHeight: Math.min(root.preferredHeight, Math.ceil(calculatedHeight))

    property real layoutWidth: Math.max(1, root.preferredWidth - Style.margin2L)

    // State (lazy-loaded with panelContent)
    property var rangeCounts: [0, 0, 0, 0]
    property var lastKnownDate: null  // Track the current date to detect day changes

    // UI state (lazy-loaded with panelContent)
    // 0 = All, 1 = Today, 2 = Yesterday, 3 = Earlier
    property int currentRange: 1  // start on Today by default
    property bool groupByDate: true
    property bool groupByApp: true
    property var groupedItems: []
    onCurrentRangeChanged: {
      resetFocus();
      recomputeGroups();
    }
    onGroupByAppChanged: recomputeGroups()

    // Keyboard navigation state
    property int focusIndex: -1
    property int actionIndex: -1  // For actions within a notification

    function resetFocus() {
      focusIndex = -1;
      actionIndex = -1;
    }

    function checkKey(event, settingName) {
      return Keybinds.checkKey(event, settingName, Settings);
    }

    // Helper functions (lazy-loaded with panelContent)
    function dateOnly(d) {
      return new Date(d.getFullYear(), d.getMonth(), d.getDate());
    }

    function getDateKey(d) {
      // Returns a string key for the date (YYYY-MM-DD) for comparison
      var date = dateOnly(d);
      return date.getFullYear() + "-" + date.getMonth() + "-" + date.getDate();
    }

    function rangeForTimestamp(ts) {
      var dt = new Date(ts);
      var today = dateOnly(new Date());
      var thatDay = dateOnly(dt);

      var diffMs = today - thatDay;
      var diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

      if (diffDays === 0)
        return 0;
      if (diffDays === 1)
        return 1;
      return 2;
    }

    function recalcRangeCounts() {
      var m = NotificationService.historyModel;
      if (!m || typeof m.count === "undefined" || m.count <= 0) {
        panelContent.rangeCounts = [0, 0, 0, 0];
        return;
      }

      var counts = [0, 0, 0, 0];

      counts[0] = m.count;

      for (var i = 0; i < m.count; ++i) {
        var item = m.get(i);
        if (!item || typeof item.timestamp === "undefined")
          continue;
        var r = rangeForTimestamp(item.timestamp);
        counts[r + 1] = counts[r + 1] + 1;
      }

      panelContent.rangeCounts = counts;
    }

    function isInCurrentRange(ts) {
      if (currentRange === 0)
        return true;
      return rangeForTimestamp(ts) === (currentRange - 1);
    }

    function countForRange(range) {
      return rangeCounts[range] || 0;
    }

    function hasNotificationsInCurrentRange() {
      var m = NotificationService.historyModel;
      if (!m || m.count === 0) {
        return false;
      }
      for (var i = 0; i < m.count; ++i) {
        var item = m.get(i);
        if (item && isInCurrentRange(item.timestamp))
          return true;
      }
      return false;
    }

    // Dismiss every member of a group (primary + extras).
    function dismissGroup(g) {
      if (!g)
        return;
      var ids = [g.primary.id];
      var ex = g.extras || [];
      for (var i = 0; i < ex.length; ++i)
        ids.push(ex[i].id);
      // Iterate snapshot-of-ids so the live recompute that happens between
      // removals doesn't affect what we iterate over.
      for (var j = 0; j < ids.length; ++j)
        NotificationService.removeFromHistory(ids[j]);
    }

    // Snapshot a historyModel item into a plain JS object so it can live in a
    // grouped JS array (binding to role objects across re-grouping is fragile).
    function snapshotItem(item) {
      return {
        id: item.id,
        appName: item.appName || "",
        summary: item.summary || "",
        body: item.body || "",
        summaryMarkdown: item.summaryMarkdown || "",
        bodyMarkdown: item.bodyMarkdown || "",
        urgency: item.urgency,
        timestamp: item.timestamp,
        cachedImage: item.cachedImage || "",
        originalImage: item.originalImage || "",
        actionsJson: item.actionsJson || "[]"
      };
    }

    // Bucket history items by (appName + calendar-day) into groups. The newest
    // item in each bucket becomes the group's primary; the rest are extras
    // (already newest-first because historyModel is newest-first).
    function recomputeGroups() {
      var m = NotificationService.historyModel;
      if (!m || m.count === 0) {
        panelContent.groupedItems = [];
        return;
      }

      // Grouping off: one single-member group per item so the delegate stays uniform.
      if (!groupByApp) {
        var flat = [];
        for (var i = 0; i < m.count; ++i) {
          var it = m.get(i);
          if (!it || typeof it.timestamp === "undefined")
            continue;
          if (!isInCurrentRange(it.timestamp))
            continue;
          flat.push({
                      "groupKey": String(it.id),
                      "appName": it.appName || "",
                      "primary": snapshotItem(it),
                      "extras": [],
                      "count": 1
                    });
        }
        panelContent.groupedItems = flat;
        return;
      }

      var byKey = {};
      var order = [];

      for (var j = 0; j < m.count; ++j) {
        var item = m.get(j);
        if (!item || typeof item.timestamp === "undefined")
          continue;
        if (!isInCurrentRange(item.timestamp))
          continue;

        var dateKey = getDateKey(new Date(item.timestamp));
        var appKey = (item.appName || "").toLowerCase();
        var key = appKey + "::" + dateKey;

        if (!byKey[key]) {
          byKey[key] = {
            "groupKey": key,
            "appName": item.appName || "",
            "primary": snapshotItem(item),
            "extras": [],
            "count": 1
          };
          order.push(key);
        } else {
          byKey[key].extras.push(snapshotItem(item));
          byKey[key].count += 1;
        }
      }

      var out = [];
      for (var k = 0; k < order.length; ++k)
        out.push(byKey[order[k]]);
      panelContent.groupedItems = out;
    }

    Component.onCompleted: {
      recalcRangeCounts();
      recomputeGroups();
      // Initialize lastKnownDate
      lastKnownDate = getDateKey(new Date());
    }

    Connections {
      target: NotificationService.historyModel
      function onCountChanged() {
        panelContent.recalcRangeCounts();
        panelContent.recomputeGroups();
      }
    }

    // Timer to check for day changes at midnight
    Timer {
      id: dayChangeTimer
      interval: 60000  // Check every minute
      repeat: true
      running: true  // Always runs when panelContent exists (panel is open)
      onTriggered: {
        var currentDateKey = panelContent.getDateKey(new Date());
        if (panelContent.lastKnownDate !== null && panelContent.lastKnownDate !== currentDateKey) {
          // Day has changed, recalculate counts
          panelContent.recalcRangeCounts();
        }
        panelContent.lastKnownDate = currentDateKey;
      }
    }

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Header section
      NBox {
        id: headerBox
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight + Style.margin2M

        ColumnLayout {
          id: header
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          RowLayout {
            id: headerRow
            NIcon {
              icon: "bell"
              pointSize: Style.fontSizeXXL
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("common.notifications")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NIconButton {
              icon: NotificationService.doNotDisturb ? "bell-off" : "bell"
              tooltipText: NotificationService.doNotDisturb ? I18n.tr("tooltips.do-not-disturb-enabled") : I18n.tr("tooltips.do-not-disturb-enabled")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: NotificationService.doNotDisturb = !NotificationService.doNotDisturb
            }

            NIconButton {
              icon: "trash"
              tooltipText: I18n.tr("actions.clear-history")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: {
                NotificationService.clearHistory();
                // Close panel as there is nothing more to see.
                root.close();
              }
            }

            NIconButton {
              icon: "settings"
              tooltipText: I18n.tr("common.settings")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: {
                SettingsPanelService.openToTab(SettingsPanel.Tab.Notifications, 0, screen);
                root.close();
              }
            }

            NIconButton {
              icon: "close"
              tooltipText: I18n.tr("common.close")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: root.close()
            }
          }

          // Time range tabs ([All] / [Today] / [Yesterday] / [Earlier])
          NTabBar {
            id: tabsBox
            Layout.fillWidth: true
            visible: NotificationService.historyModel.count > 0 && panelContent.groupByDate
            currentIndex: panelContent.currentRange
            tabHeight: Style.toOdd(Style.baseWidgetSize * 0.8)
            spacing: Style.marginXS
            distributeEvenly: true

            NTabButton {
              tabIndex: 0
              text: I18n.tr("launcher.categories.all") + " (" + panelContent.countForRange(0) + ")"
              checked: tabsBox.currentIndex === 0
              onClicked: panelContent.currentRange = 0
              pointSize: Style.fontSizeXS
            }

            NTabButton {
              tabIndex: 1
              text: I18n.tr("notifications.range.today") + " (" + panelContent.countForRange(1) + ")"
              checked: tabsBox.currentIndex === 1
              onClicked: panelContent.currentRange = 1
              pointSize: Style.fontSizeXS
            }

            NTabButton {
              tabIndex: 2
              text: I18n.tr("notifications.range.yesterday") + " (" + panelContent.countForRange(2) + ")"
              checked: tabsBox.currentIndex === 2
              onClicked: panelContent.currentRange = 2
              pointSize: Style.fontSizeXS
            }

            NTabButton {
              tabIndex: 3
              text: I18n.tr("notifications.range.earlier") + " (" + panelContent.countForRange(3) + ")"
              checked: tabsBox.currentIndex === 3
              onClicked: panelContent.currentRange = 3
              pointSize: Style.fontSizeXS
            }
          }
        }
      }

      // Notification list container with gradient overlay
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        NScrollView {
          id: scrollView
          anchors.fill: parent
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded
          reserveScrollbarSpace: false
          gradientColor: Color.mSurface

          // Track which notification is expanded (truncated text reveal)
          property string expandedId: ""
          // Track which app-group is expanded (extras list reveal)
          property string expandedGroupKey: ""

          ColumnLayout {
            width: panelContent.layoutWidth
            spacing: Style.marginM

            // Empty state when no notifications
            NBox {
              visible: !panelContent.hasNotificationsInCurrentRange()
              Layout.fillWidth: true
              Layout.preferredHeight: emptyState.implicitHeight + Style.marginXL

              ColumnLayout {
                id: emptyState
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                Item {
                  Layout.fillHeight: true
                }

                NIcon {
                  icon: "bell-off"
                  pointSize: (NotificationService.historyModel.count === 0) ? 48 : Style.baseWidgetSize
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }

                NText {
                  text: I18n.tr("notifications.panel.no-notifications")
                  pointSize: (NotificationService.historyModel.count === 0) ? Style.fontSizeL : Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }

                NText {
                  visible: NotificationService.historyModel.count === 0
                  text: I18n.tr("notifications.panel.description")
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurfaceVariant
                  horizontalAlignment: Text.AlignHCenter
                  Layout.fillWidth: true
                  wrapMode: Text.WordWrap
                }

                Item {
                  Layout.fillHeight: true
                }
              }
            }

            // Notification list container
            Item {
              visible: panelContent.hasNotificationsInCurrentRange()
              Layout.fillWidth: true
              Layout.preferredHeight: notificationColumn.implicitHeight

              Column {
                id: notificationColumn
                width: panelContent.layoutWidth
                spacing: Style.marginM

                Repeater {
                  model: panelContent.groupedItems

                  delegate: Item {
                    id: notificationDelegate
                    width: parent.width
                    visible: !isRemoving
                    height: visible ? contentColumn.height + Style.margin2M : 0

                    // Group payload. `modelData` and `index` are injected by Repeater.
                    property var primary: modelData.primary
                    property var extras: modelData.extras || []
                    property string groupKey: modelData.groupKey
                    property int groupCount: modelData.count || 1
                    property bool isGroup: groupCount > 1
                    property bool isGroupExpanded: scrollView.expandedGroupKey === groupKey

                    property int listIndex: index
                    property string notificationId: primary.id
                    property string appName: primary.appName || ""
                    property bool isExpanded: scrollView.expandedId === notificationId
                    property bool canExpand: summaryText.truncated || bodyText.truncated
                    property real swipeOffset: 0
                    property real pressGlobalX: 0
                    property real pressGlobalY: 0
                    property bool isSwiping: false
                    property bool isRemoving: false
                    property string pendingLink: ""
                    readonly property real swipeStartThreshold: Math.round(16 * Style.uiScaleRatio)
                    readonly property real swipeDismissThreshold: Math.max(110, width * 0.3)
                    readonly property int removeAnimationDuration: Style.animationNormal
                    readonly property int notificationTextFormat: (Settings.data.notifications.enableMarkdown && notificationDelegate.isExpanded) ? Text.MarkdownText : Text.StyledText
                    readonly property real actionButtonSize: Style.baseWidgetSize * 0.7
                    readonly property int buttonClusterCount: notificationDelegate.isGroup ? 3 : 2
                    readonly property real buttonClusterWidth: notificationDelegate.actionButtonSize * buttonClusterCount
                                                               + Style.marginXS * Math.max(0, buttonClusterCount - 1)
                    readonly property real iconSize: Math.round(40 * Style.uiScaleRatio)

                    function isSafeLink(link) {
                      if (!link)
                        return false;
                      const lower = link.toLowerCase();
                      const schemes = ["http://", "https://", "mailto:"];
                      return schemes.some(scheme => lower.startsWith(scheme));
                    }

                    function linkAtPoint(x, y) {
                      if (!Settings.data.notifications.enableMarkdown || !notificationDelegate.isExpanded)
                        return "";

                      if (summaryText) {
                        const summaryPoint = summaryText.mapFromItem(historyInteractionArea, x, y);
                        if (summaryPoint.x >= 0 && summaryPoint.y >= 0 && summaryPoint.x <= summaryText.width && summaryPoint.y <= summaryText.height) {
                          const summaryLink = summaryText.linkAt ? summaryText.linkAt(summaryPoint.x, summaryPoint.y) : "";
                          if (isSafeLink(summaryLink))
                            return summaryLink;
                        }
                      }

                      if (bodyText) {
                        const bodyPoint = bodyText.mapFromItem(historyInteractionArea, x, y);
                        if (bodyPoint.x >= 0 && bodyPoint.y >= 0 && bodyPoint.x <= bodyText.width && bodyPoint.y <= bodyText.height) {
                          const bodyLink = bodyText.linkAt ? bodyText.linkAt(bodyPoint.x, bodyPoint.y) : "";
                          if (isSafeLink(bodyLink))
                            return bodyLink;
                        }
                      }

                      return "";
                    }

                    function updateCursorAt(x, y) {
                      if (notificationDelegate.isExpanded && notificationDelegate.linkAtPoint(x, y)) {
                        historyInteractionArea.cursorShape = Qt.PointingHandCursor;
                      } else {
                        historyInteractionArea.cursorShape = Qt.ArrowCursor;
                      }
                    }

                    transform: Translate {
                      x: notificationDelegate.swipeOffset
                    }

                    function dismissBySwipe() {
                      if (isRemoving)
                        return;
                      isRemoving = true;
                      isSwiping = false;

                      if (Settings.data.general.animationDisabled) {
                        if (notificationDelegate.isGroup)
                          panelContent.dismissGroup(modelData);
                        else
                          NotificationService.removeFromHistory(notificationId);
                        return;
                      }

                      swipeOffset = swipeOffset >= 0 ? width + Style.marginL : -width - Style.marginL;
                      opacity = 0;
                      removeTimer.restart();
                    }

                    Timer {
                      id: removeTimer
                      interval: notificationDelegate.removeAnimationDuration
                      repeat: false
                      onTriggered: {
                        if (notificationDelegate.isGroup)
                          panelContent.dismissGroup(modelData);
                        else
                          NotificationService.removeFromHistory(notificationId);
                      }
                    }

                    Behavior on swipeOffset {
                      enabled: !Settings.data.general.animationDisabled && !notificationDelegate.isSwiping
                      NumberAnimation {
                        duration: notificationDelegate.removeAnimationDuration
                        easing.type: Easing.OutCubic
                      }
                    }

                    Behavior on opacity {
                      enabled: !Settings.data.general.animationDisabled && notificationDelegate.isRemoving
                      NumberAnimation {
                        duration: notificationDelegate.removeAnimationDuration
                        easing.type: Easing.OutCubic
                      }
                    }

                    Behavior on height {
                      enabled: !Settings.data.general.animationDisabled && notificationDelegate.isRemoving
                      NumberAnimation {
                        duration: notificationDelegate.removeAnimationDuration
                        easing.type: Easing.OutCubic
                      }
                    }

                    Behavior on y {
                      enabled: !Settings.data.general.animationDisabled && notificationDelegate.isRemoving
                      NumberAnimation {
                        duration: notificationDelegate.removeAnimationDuration
                        easing.type: Easing.OutCubic
                      }
                    }

                    // Parse actions safely
                    property var actionsList: parseActions(notificationDelegate.primary.actionsJson)

                    property bool isFocused: index === panelContent.focusIndex

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.radiusM
                      color: Color.mSurfaceVariant
                      border.color: {
                        if (notificationDelegate.isFocused)
                          return Color.mPrimary;
                        if (Settings.data.ui.boxBorderEnabled)
                          return Qt.alpha(Color.mOutline, Style.opacityHeavy);
                        return "transparent";
                      }
                      border.width: notificationDelegate.isFocused ? Style.borderM : Style.borderS

                      Behavior on color {
                        enabled: !Settings.data.general.animationDisabled
                        ColorAnimation {
                          duration: Style.animationFast
                        }
                      }
                    }

                    // Click to expand/collapse
                    MouseArea {
                      id: historyInteractionArea
                      anchors.fill: parent
                      anchors.rightMargin: notificationDelegate.buttonClusterWidth + Style.marginM
                      enabled: !notificationDelegate.isRemoving
                      hoverEnabled: true
                      cursorShape: Qt.ArrowCursor
                      onPressed: mouse => {
                                   panelContent.focusIndex = index;
                                   panelContent.actionIndex = -1;

                                   if (notificationDelegate.isExpanded) {
                                     const link = notificationDelegate.linkAtPoint(mouse.x, mouse.y);
                                     if (link) {
                                       notificationDelegate.pendingLink = link;
                                     } else {
                                       notificationDelegate.pendingLink = "";
                                     }
                                   }

                                   if (mouse.button !== Qt.LeftButton)
                                   return;
                                   const globalPoint = historyInteractionArea.mapToGlobal(mouse.x, mouse.y);
                                   notificationDelegate.pressGlobalX = globalPoint.x;
                                   notificationDelegate.pressGlobalY = globalPoint.y;
                                   notificationDelegate.isSwiping = false;
                                 }
                      onPositionChanged: mouse => {
                                           if (!(mouse.buttons & Qt.LeftButton) || notificationDelegate.isRemoving)
                                           return;

                                           const globalPoint = historyInteractionArea.mapToGlobal(mouse.x, mouse.y);
                                           const deltaX = globalPoint.x - notificationDelegate.pressGlobalX;
                                           const deltaY = globalPoint.y - notificationDelegate.pressGlobalY;

                                           if (!notificationDelegate.isSwiping) {
                                             if (Math.abs(deltaX) < notificationDelegate.swipeStartThreshold)
                                             return;

                                             // Only start a swipe-dismiss when horizontal movement is dominant.
                                             if (Math.abs(deltaX) <= Math.abs(deltaY) * 1.15) {
                                               return;
                                             }
                                             notificationDelegate.isSwiping = true;
                                           }

                                           if (notificationDelegate.pendingLink && Math.abs(deltaX) >= notificationDelegate.swipeStartThreshold) {
                                             notificationDelegate.pendingLink = "";
                                           }

                                           notificationDelegate.swipeOffset = deltaX;
                                         }
                      onReleased: mouse => {
                                    if (mouse.button !== Qt.LeftButton)
                                    return;

                                    if (notificationDelegate.isSwiping) {
                                      if (Math.abs(notificationDelegate.swipeOffset) >= notificationDelegate.swipeDismissThreshold) {
                                        notificationDelegate.dismissBySwipe();
                                      } else {
                                        notificationDelegate.swipeOffset = 0;
                                      }
                                      notificationDelegate.isSwiping = false;
                                      notificationDelegate.pendingLink = "";
                                      return;
                                    }

                                    if (notificationDelegate.pendingLink) {
                                      Qt.openUrlExternally(notificationDelegate.pendingLink);
                                      notificationDelegate.pendingLink = "";
                                      return;
                                    }

                                    // Without a default action, or if invoking it fails,
                                    // fall back to focusing the sender window by app identity.
                                    var actions = notificationDelegate.actionsList;
                                    var hasDefault = actions.some(function (a) {
                                      return a.identifier === "default";
                                    });
                                    if (hasDefault && NotificationService.invokeAction(notificationDelegate.notificationId, "default")) {
                                      root.close();
                                    } else {
                                      NotificationService.focusSenderWindow(notificationDelegate.appName);
                                      root.close();
                                    }
                                  }
                      onCanceled: {
                        notificationDelegate.isSwiping = false;
                        notificationDelegate.swipeOffset = 0;
                        notificationDelegate.pendingLink = "";
                        historyInteractionArea.cursorShape = Qt.ArrowCursor;
                      }
                    }

                    HoverHandler {
                      target: historyInteractionArea
                      onPointChanged: notificationDelegate.updateCursorAt(point.position.x, point.position.y)
                      onActiveChanged: {
                        if (!active) {
                          historyInteractionArea.cursorShape = Qt.ArrowCursor;
                        }
                      }
                    }

                    onVisibleChanged: {
                      if (!visible) {
                        notificationDelegate.isSwiping = false;
                        notificationDelegate.swipeOffset = 0;
                        notificationDelegate.opacity = 1;
                        notificationDelegate.isRemoving = false;
                        removeTimer.stop();
                      }
                    }

                    Component.onDestruction: removeTimer.stop()

                    Column {
                      id: contentColumn
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.marginM
                      spacing: Style.marginM

                      Row {
                        width: parent.width
                        spacing: Style.marginM

                        // Icon
                        NImageRounded {
                          anchors.verticalCenter: notificationDelegate.isExpanded ? undefined : parent.verticalCenter
                          width: notificationDelegate.iconSize
                          height: notificationDelegate.iconSize
                          radius: Math.min(Style.radiusL, width / 2)
                          imagePath: notificationDelegate.primary.cachedImage || notificationDelegate.primary.originalImage || ""
                          borderColor: "transparent"
                          borderWidth: 0
                          fallbackIcon: "bell"
                          fallbackIconSize: 24
                        }

                        // Content
                        Column {
                          width: parent.width - notificationDelegate.iconSize - notificationDelegate.buttonClusterWidth - Style.margin2M
                          spacing: Style.marginXS

                          // Header row with app name and timestamp
                          Row {
                            width: parent.width
                            spacing: Style.marginS

                            // Urgency indicator
                            Rectangle {
                              width: 6
                              height: 6
                              anchors.verticalCenter: parent.verticalCenter
                              radius: 3
                              visible: notificationDelegate.primary.urgency !== 1
                              color: {
                                if (notificationDelegate.primary.urgency === 2)
                                  return Color.mError;
                                else if (notificationDelegate.primary.urgency === 0)
                                  return Color.mOnSurfaceVariant;
                                else
                                  return "transparent";
                              }
                            }

                            NText {
                              text: notificationDelegate.primary.appName || "Unknown App"
                              pointSize: Style.fontSizeXS
                              font.weight: Style.fontWeightBold
                              color: Color.mSecondary
                            }

                            // Group count pill (e.g. "3") — shown only when the group has extras.
                            Rectangle {
                              visible: notificationDelegate.isGroup
                              anchors.verticalCenter: parent.verticalCenter
                              implicitHeight: Math.round(14 * Style.uiScaleRatio)
                              implicitWidth: Math.max(implicitHeight, countLabel.implicitWidth + Style.marginS * 2)
                              radius: implicitHeight / 2
                              color: Color.mPrimary

                              NText {
                                id: countLabel
                                anchors.centerIn: parent
                                text: notificationDelegate.groupCount
                                pointSize: Style.fontSizeXXS
                                font.weight: Style.fontWeightBold
                                color: Color.mOnPrimary
                              }
                            }

                            NText {
                              textFormat: Text.PlainText
                              text: " " + Time.formatRelativeTime(notificationDelegate.primary.timestamp)
                              pointSize: Style.fontSizeXXS
                              color: Color.mOnSurfaceVariant
                              anchors.bottom: parent.bottom
                            }
                          }

                          // Summary
                          NText {
                            id: summaryText
                            width: parent.width
                            text: (Settings.data.notifications.enableMarkdown && notificationDelegate.isExpanded) ? (notificationDelegate.primary.summaryMarkdown || I18n.tr("common.no-summary")) : (notificationDelegate.primary.summary || I18n.tr("common.no-summary"))
                            pointSize: Style.fontSizeM
                            color: Color.mOnSurface
                            textFormat: notificationDelegate.notificationTextFormat
                            wrapMode: Text.Wrap
                            maximumLineCount: notificationDelegate.isExpanded ? 999 : 2
                            elide: Text.ElideRight
                          }

                          // Body
                          NText {
                            id: bodyText
                            width: parent.width
                            text: (Settings.data.notifications.enableMarkdown && notificationDelegate.isExpanded) ? (notificationDelegate.primary.bodyMarkdown || "") : (notificationDelegate.primary.body || "")
                            pointSize: Style.fontSizeS
                            color: Color.mOnSurfaceVariant
                            textFormat: notificationDelegate.notificationTextFormat
                            wrapMode: Text.Wrap
                            maximumLineCount: notificationDelegate.isExpanded ? 999 : 3
                            elide: Text.ElideRight
                            visible: text.length > 0
                          }

                          // Actions Flow
                          Flow {
                            width: parent.width
                            spacing: Style.marginS
                            visible: notificationDelegate.actionsList.length > 0

                            Repeater {
                              model: notificationDelegate.actionsList

                              delegate: NButton {
                                text: modelData.text
                                fontSize: Style.fontSizeS

                                readonly property bool actionNavActive: notificationDelegate.isFocused && panelContent.actionIndex !== -1
                                readonly property bool isSelected: actionNavActive && panelContent.actionIndex === index

                                backgroundColor: isSelected ? Color.mSecondary : Color.mPrimary
                                textColor: isSelected ? Color.mOnSecondary : Color.mOnPrimary

                                outlined: false
                                implicitHeight: 24

                                onHoveredChanged: {
                                  if (hovered) {
                                    panelContent.focusIndex = notificationDelegate.listIndex;
                                  }
                                }

                                // Capture modelData in a property to avoid reference errors
                                property var actionData: modelData
                                onClicked: {
                                  if (NotificationService.invokeAction(notificationDelegate.notificationId, actionData.identifier))
                                    root.close();
                                }
                              }
                            }
                          }
                        }

                        Item {
                          width: notificationDelegate.buttonClusterWidth
                          height: notificationDelegate.actionButtonSize

                          Row {
                            anchors.right: parent.right
                            spacing: Style.marginXS

                            NIconButton {
                              id: expandButton
                              icon: notificationDelegate.isExpanded ? "chevron-up" : "chevron-down"
                              tooltipText: notificationDelegate.isExpanded ? I18n.tr("notifications.panel.click-to-collapse") || "Click to collapse" : I18n.tr("notifications.panel.click-to-expand") || "Click to expand"
                              baseSize: notificationDelegate.actionButtonSize
                              opacity: (notificationDelegate.canExpand || notificationDelegate.isExpanded) ? 1.0 : 0.0
                              enabled: notificationDelegate.canExpand || notificationDelegate.isExpanded

                              onClicked: {
                                notificationDelegate.pendingLink = "";
                                historyInteractionArea.cursorShape = Qt.ArrowCursor;
                                if (scrollView.expandedId === notificationId) {
                                  scrollView.expandedId = "";
                                } else {
                                  scrollView.expandedId = notificationId;
                                }
                              }
                            }

                            // Group expand/collapse — only present when the group has extras.
                            NIconButton {
                              id: groupExpandButton
                              visible: notificationDelegate.isGroup
                              icon: notificationDelegate.isGroupExpanded ? "chevrons-up" : "chevrons-down"
                              tooltipText: notificationDelegate.isGroupExpanded ? (I18n.tr("notifications.panel.click-to-collapse") || "Click to collapse") : (I18n.tr("notifications.panel.click-to-expand") || "Click to expand")
                              baseSize: notificationDelegate.actionButtonSize

                              onClicked: {
                                notificationDelegate.pendingLink = "";
                                historyInteractionArea.cursorShape = Qt.ArrowCursor;
                                if (scrollView.expandedGroupKey === notificationDelegate.groupKey) {
                                  scrollView.expandedGroupKey = "";
                                } else {
                                  scrollView.expandedGroupKey = notificationDelegate.groupKey;
                                }
                              }
                            }

                            // Delete button — dismisses the entire stack on a grouped card.
                            NIconButton {
                              icon: "trash"
                              tooltipText: notificationDelegate.isGroup
                                           ? (I18n.tr("tooltips.delete-notification") + " (" + notificationDelegate.groupCount + ")")
                                           : I18n.tr("tooltips.delete-notification")
                              baseSize: notificationDelegate.actionButtonSize

                              onClicked: {
                                if (notificationDelegate.isGroup) {
                                  panelContent.dismissGroup(modelData);
                                } else {
                                  NotificationService.removeFromHistory(notificationId);
                                }
                              }
                            }
                          }
                        }
                      }

                      // Older members of the same app-group, revealed when expanded.
                      // NOTE: must not use anchors here — contentColumn is a Column positioner,
                      // and anchored children get ignored from its height calc (card outline wouldn't grow).
                      Column {
                        id: extrasColumn
                        width: parent.width
                        spacing: Style.marginXS
                        visible: notificationDelegate.isGroup && notificationDelegate.isGroupExpanded

                        Repeater {
                          model: notificationDelegate.extras

                          delegate: Rectangle {
                            id: extraRow
                            required property var modelData
                            width: parent.width
                            implicitHeight: Math.max(extraTrash.height, extraTextCol.implicitHeight) + Style.marginXS * 2
                            color: extraHover.containsMouse ? Qt.alpha(Color.mOnSurface, Style.opacityLight) : "transparent"
                            radius: Style.radiusS

                            // Click-target sits BELOW the children so the trash button stays clickable.
                            MouseArea {
                              id: extraHover
                              anchors.fill: parent
                              anchors.rightMargin: extraTrash.width + Style.marginS
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                var actions = parseActions(extraRow.modelData.actionsJson);
                                var hasDefault = actions.some(function (a) {
                                  return a.identifier === "default";
                                });
                                if (hasDefault && NotificationService.invokeAction(extraRow.modelData.id, "default")) {
                                  root.close();
                                } else {
                                  NotificationService.focusSenderWindow(extraRow.modelData.appName);
                                  root.close();
                                }
                              }
                            }

                            NIconButton {
                              id: extraTrash
                              icon: "trash"
                              tooltipText: I18n.tr("tooltips.delete-notification")
                              baseSize: notificationDelegate.actionButtonSize
                              anchors.right: parent.right
                              anchors.rightMargin: Style.marginXS
                              anchors.verticalCenter: parent.verticalCenter
                              onClicked: NotificationService.removeFromHistory(extraRow.modelData.id)
                            }

                            NText {
                              id: extraTime
                              textFormat: Text.PlainText
                              text: Time.formatRelativeTime(extraRow.modelData.timestamp)
                              pointSize: Style.fontSizeXXS
                              color: Color.mOnSurfaceVariant
                              anchors.right: extraTrash.left
                              anchors.rightMargin: Style.marginS
                              anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                              id: extraTextCol
                              anchors.left: parent.left
                              anchors.right: extraTime.left
                              anchors.leftMargin: notificationDelegate.iconSize + Style.marginM
                              anchors.rightMargin: Style.marginS
                              anchors.verticalCenter: parent.verticalCenter
                              spacing: 0

                              NText {
                                width: parent.width
                                text: extraRow.modelData.summary || I18n.tr("common.no-summary")
                                pointSize: Style.fontSizeS
                                color: Color.mOnSurface
                                elide: Text.ElideRight
                                maximumLineCount: 1
                              }

                              NText {
                                width: parent.width
                                visible: (extraRow.modelData.body || "").length > 0
                                text: extraRow.modelData.body || ""
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurfaceVariant
                                elide: Text.ElideRight
                                maximumLineCount: 1
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
