import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Brand.js" as Brand

BarWidget {
  id: root
  moduleName: "datadog.lapdog"
  property bool menuOpen: false
  property string state: "loading"
  property string label: "Checking"
  property string summary: "Loading latest session…"
  property string detail: ""
  property string sessionId: ""
  property string traces: "—"
  property string cost: "—"
  property string started: "—"
  property string duration: "—"
  property string application: "—"
  property string project: "—"
  property string models: "—"
  property string errors: "—"
  property string calls: "—"
  property string tokens: "—"
  property var spanKinds: []
  property string spanCount: "—"
  property var activity: []
  property var waterfall: []
  property real traceDuration: 1
  property string traceId: ""
  property bool expanded: false
  property var sessions: []
  property int recentSessions: 0
  property bool sessionIndexTruncated: false
  property string selectedSession: ""
  property string requestedSession: ""
  property bool sessionRefreshQueued: false
  property var sessionCache: ({})
  property string warmingSession: ""
  function localPath(fileName) {
    var url = String(Qt.resolvedUrl(fileName))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
  }
  readonly property color foreground: Brand.purple1
  readonly property color dim: "#bdbdbd"
  readonly property color dotColor: state === "running" ? Brand.green : Brand.yellow
  readonly property bool opened: menuOpen
  function open() { menuOpen = true; refresh() }
  function close() { menuOpen = false }
  function toggle() { menuOpen ? close() : open() }
  function closeForPopoutSwitch() { close() }
  function refresh() {
    if (!statusProc.running) {
      requestedSession = selectedSession
      statusProc.running = true
    }
  }
  function rememberSession(data) {
    if (data.sessionId && data.state === "running") {
      sessionCache[data.sessionId] = {data: data, saved: Date.now()}
    }
  }
  function warmNextSession() {
    if (!menuOpen || warmProc.running || statusProc.running) return
    var current = selectedSession || sessionId
    for (var i = 0; i < sessions.length; ++i) {
      var id = sessions[i].id
      if (id === current) continue
      var cached = sessionCache[id]
      if (!cached || Date.now() - cached.saved > 60000) {
        warmingSession = id
        sessionCache[id] = {data: cached ? cached.data : null, saved: Date.now()}
        warmProc.running = true
        return
      }
    }
  }
  function selectSession(id) {
    selectedSession = id
    var cached = sessionCache[id]
    if (cached && cached.data) applyStatus(JSON.stringify(cached.data), true)
    else {
      sessionId = id
      var item = sessions.find(function(s) { return s.id === id })
      application = item ? item.application : "—"
      project = item ? item.project : "—"
      traces = cost = started = duration = models = errors = calls = tokens = spanCount = "—"
      activity = []; waterfall = []; spanKinds = []; traceId = ""
      summary = "Loading session details…"
    }
    if (statusProc.running) sessionRefreshQueued = true
    else refresh()
  }
  function applyStatus(output, fromCache) {
    try {
      var data = JSON.parse(String(output || "{}"))
      if (!fromCache) rememberSession(data)
      if (!fromCache && requestedSession !== selectedSession) return
      state = data.state || "error"
      label = data.label || "Unavailable"
      summary = data.summary || "Session data unavailable"
      detail = data.detail || ""
      sessionId = data.sessionId || ""
      if (!fromCache) {
        if (!sessionPicker.popup.visible) sessions = data.sessions || []
        recentSessions = data.recentSessions || 0
        sessionIndexTruncated = !!data.sessionIndexTruncated
      }
      traces = data.traces || "—"
      cost = data.cost || "—"
      started = data.started || "—"
      duration = data.duration || "—"
      application = data.application || "—"
      project = data.project || "—"
      models = data.models || "—"
      errors = data.errors || "—"
      calls = data.calls || "—"
      tokens = data.tokens || "—"
      spanKinds = data.spanKinds || []
      spanCount = data.spanCount || "—"
      activity = data.activity || []
      waterfall = data.waterfall || []
      traceDuration = data.traceDuration || 1
      traceId = data.traceId || ""
    } catch (error) {
      state = "error"
      label = "Unavailable"
      summary = "Could not read session data"
      detail = String(error)
      sessionId = ""
      traces = cost = started = duration = "—"
      application = project = models = errors = calls = tokens = "—"
      spanKinds = []
      spanCount = "—"
      activity = []; waterfall = []; traceId = ""
    }
  }
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  Process {
    id: statusProc
    command: [root.localPath("lapdog-status.py"), root.requestedSession]
    onRunningChanged: {
      if (!running && root.sessionRefreshQueued) {
        root.sessionRefreshQueued = false
        Qt.callLater(root.refresh)
      } else if (!running) Qt.callLater(root.warmNextSession)
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }
  Process {
    id: warmProc
    command: [root.localPath("lapdog-status.py"), root.warmingSession]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.rememberSession(JSON.parse(text)) } catch (error) {}
      }
    }
    onRunningChanged: if (!running) Qt.callLater(root.warmNextSession)
  }
  Timer {
    interval: root.menuOpen ? 10000 : 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    slotSize: Style.space(100)
    tooltipText: "Lapdog: " + root.label + " · " + root.sessions.length + " sessions / " + root.recentSessions + " recent" + (root.sessionId ? " · " + root.traces + " traces · " + root.cost : "")
    iconComponent: Component {
      Item {
        Image {
          id: logoMask
          anchors.centerIn: parent
          width: Style.space(80)
          height: Style.space(18)
          source: Qt.resolvedUrl("lapdog_logo.svg")
          fillMode: Image.PreserveAspectFit
        }
        Rectangle {
          width: Style.space(6)
          height: width
          radius: width / 2
          anchors.left: logoMask.right
          anchors.leftMargin: Style.space(3)
          anchors.verticalCenter: logoMask.verticalCenter
          color: root.dotColor
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else if (buttonCode === Qt.RightButton && root.bar) root.bar.run("gtk-launch LapDog")
      else root.toggle()
    }
  }
  KeyboardPanel {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.menuOpen
    contentWidth: Style.space(root.expanded ? 900 : 360)
    contentHeight: Style.space(root.expanded ? 1120 : 1000)
    PurpleAtmosphere {
      anchors.fill: parent
      anchors.margins: -Style.space(8)
      animate: root.menuOpen
    }
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(12)
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(36)
        radius: Style.space(8)
        color: datadogMouse.containsMouse ? Brand.purple2 : Brand.purple3
        Text {
          anchors.centerIn: parent
          text: "View in Datadog"
          color: "white"
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
        MouseArea {
          id: datadogMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.bar) root.bar.run("xdg-open https://app.datadoghq.com/llm/traces")
            root.close()
          }
        }
      }
      RowLayout {
        Layout.fillWidth: true
        Image {
          source: Qt.resolvedUrl("lapdog_logo.svg")
          fillMode: Image.PreserveAspectFit
          horizontalAlignment: Image.AlignLeft
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(28)
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.bar) root.bar.run("gtk-launch LapDog")
              root.close()
            }
          }
        }
        Rectangle {
          Layout.preferredWidth: statusPill.implicitWidth + Style.space(20)
          Layout.preferredHeight: Style.space(26)
          radius: Style.space(13)
          color: root.state === "running" ? Qt.rgba(0, 227/255, 125/255, 0.12) : Qt.rgba(255/255, 155/255, 0, 0.12)
          border.color: root.dotColor
          Text {
            id: statusPill
            anchors.centerIn: parent
            text: (root.state === "running" ? "● " : "○ ") + root.label.toUpperCase()
            color: root.dotColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)
        Text {
          Layout.fillWidth: true
          text: root.sessions.length + " sessions · " + root.recentSessions + " recent · " + (root.sessions.length - root.recentSessions) + " older"
          color: Brand.purple2
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
        ComboBox {
          id: sessionPicker
          Layout.fillWidth: true
          enabled: root.sessions.length > 0
          model: root.sessions
          textRole: "display"
          currentIndex: root.sessions.findIndex(function(s) { return s.id === root.sessionId })
          onActivated: function(index) { root.selectSession(root.sessions[index].id) }
          contentItem: Text {
            text: sessionPicker.currentText || "No recorded sessions"
            color: root.foreground
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            leftPadding: Style.space(8)
            rightPadding: Style.space(20)
          }
          indicator: Text {
            text: "▾"; color: Brand.purple2
            anchors.right: parent.right; anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
          }
          background: Rectangle { color: "#141414"; radius: 6; border.color: Brand.purple3 }
          delegate: ItemDelegate {
            required property var modelData
            width: sessionPicker.width
            contentItem: Text { text: modelData.display; color: root.foreground; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            background: Rectangle { color: parent.hovered ? Brand.purple5 : "#141414" }
          }
          popup: Popup {
            enter: Transition {}
            exit: Transition {}
            y: sessionPicker.height
            width: sessionPicker.width
            padding: 1
            implicitHeight: Math.min(contentItem.implicitHeight + 2, Style.space(220))
            background: Rectangle { color: "#141414"; border.color: Brand.purple3; radius: 6 }
            contentItem: ListView {
              clip: true; implicitHeight: contentHeight
              model: sessionPicker.popup.visible ? sessionPicker.delegateModel : null
              ScrollBar.vertical: ScrollBar {}
            }
          }
        }
        Text {
          Layout.fillWidth: true
          text: "Recent = reported within 5 min, not process status.\n" + (root.sessionIndexTruncated ? "Showing sessions in the latest 1,000 spans." : "Showing all recorded sessions.")
          color: root.dim; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
        }
      }
      RowLayout {
        spacing: Style.space(8)
        Text {
          text: "Observe"
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Rectangle {
          Layout.preferredWidth: Style.space(24)
          Layout.preferredHeight: Style.space(24)
          radius: Style.space(6)
          color: "#090909"
          border.color: Brand.purple3
          visible: ["pi", "pi-coding-agent", "pi coding agent"].indexOf(root.application.toLowerCase()) >= 0
          Image {
            anchors.centerIn: parent
            width: parent.width * 0.75
            height: width
            source: Qt.resolvedUrl("pi_reversed_avatar.svg")
            fillMode: Image.PreserveAspectFit
          }
        }
        Text {
          text: root.application === "pi-coding-agent" ? "Pi" : root.application
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          text: "in real-time as you code."
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(310)
        radius: Style.space(8)
        color: "#80141414"
        border.color: Brand.purple3
        border.width: 1
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(8)
          StatusRow {
            label: "Application"
            value: root.application
            iconSource: ["pi", "pi-coding-agent", "pi coding agent"].indexOf(root.application.toLowerCase()) >= 0
                        ? Qt.resolvedUrl("pi_reversed_avatar.svg") : ""
          }
          StatusRow { label: "Project"; value: root.project }
          StatusRow { label: "Models"; value: root.models }
          StatusRow { label: "Total Traces"; value: root.traces }
          StatusRow { label: "Errors (spans)"; value: root.errors }
          StatusRow { label: "Calls"; value: root.calls }
          StatusRow { label: "Tokens"; value: root.tokens }
          StatusRow { label: "Estimated Cost"; value: root.cost }
          StatusRow { label: "Started"; value: root.started }
          StatusRow { label: "Duration"; value: root.duration }
        }
      }
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          elide: Text.ElideRight
          text: "SESSION OBSERVATORY · " + root.spanCount + " spans"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
        Text {
          text: root.expanded ? "↙ Compact" : "↗ Expand"
          color: Brand.purple2
          font.pixelSize: Style.font.bodySmall
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
          }
        }
      }
      Text {
        text: "Agent · purple    LLM · blue    Tool · cyan    Step · vivid purple\nErrors · red    Cost per interval · amber (independent scale)"
        color: root.dim
        font.pixelSize: Style.font.caption
      }
      SessionChart {
        id: activityChart
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(root.expanded ? 180 : 130)
        samples: root.activity
        foreground: root.foreground
      }
      Text {
        Layout.fillWidth: true
        text: activityChart.hoverText || "Hover over the skyline to inspect activity and cost per interval"
        color: root.dim
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Text {
        text: "LATEST TRACE · " + root.waterfall.length + " spans"
        color: root.foreground
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      SessionChart {
        id: traceChart
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(root.expanded ? 220 : 150)
        waterfall: true
        spans: root.waterfall
        traceDuration: root.traceDuration
        foreground: root.foreground
      }
      Text {
        Layout.fillWidth: true
        text: traceChart.hoverText || "Time-aligned spans · hover for kind, name, duration and parent depth"
        color: root.dim
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Text {
        Layout.fillWidth: true
        text: root.detail || (root.sessionId ? "Session: " + root.sessionId : "No session available")
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WrapAnywhere
      }
      Text {
        Layout.fillWidth: true
        text: "Latest activity · Duration spans first to last recorded event\nMiddle-click refreshes · Right-click opens Lapdog"
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      Item { Layout.fillHeight: true }
    }
    component StatusRow: RowLayout {
      id: statusRow
      property string label: ""
      property string value: ""
      property string iconSource: ""
      Layout.fillWidth: true
      Text {
        text: parent.label
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Item { Layout.fillWidth: true }
      Image {
        source: statusRow.iconSource
        visible: statusRow.iconSource !== "" && status !== Image.Error
        Layout.preferredWidth: Style.space(20)
        Layout.preferredHeight: Style.space(20)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
      }
      Text {
        Layout.maximumWidth: Style.space(root.expanded ? 680 : 140)
        horizontalAlignment: Text.AlignRight
        text: statusRow.value
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }
    }
  }
}
