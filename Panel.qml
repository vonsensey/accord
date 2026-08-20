import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Accord panel: the palette that was actually written, shown as a living
// preview - a mock libadwaita window painted from state.json, the swatch
// strip with hex values, and the exact files and settings Accord touched.
// Keyboard: a applies now, Esc closes.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  readonly property var pal: service && service.palette ? service.palette : null
  readonly property var st: service && service.state ? service.state : null

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function close() { root.opened = false }
  function toggle() { root.opened ? close() : open("{}") }

  // Surface chrome uses the shell's menu tokens; the mock window deliberately
  // uses raw palette values from state.json - it previews what was written,
  // not what the shell theme resolves to.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property string fontFamily: Style.font.menuFamily

  function palColor(key, fallback) {
    return root.pal && root.pal[key] ? root.pal[key] : fallback
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-accord"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: Math.min(Style.space(660), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
          else if (event.key === Qt.Key_A) {
            if (root.service) root.service.applyNow()
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        // ------------------------------------------------------------ header
        Item {
          width: parent.width
          height: title.implicitHeight

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Accord"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Rectangle {
              visible: root.st !== null
              implicitWidth: modeLabel.implicitWidth + Style.space(12)
              implicitHeight: modeLabel.implicitHeight + Style.space(4)
              radius: implicitHeight / 2
              color: "transparent"
              border.color: root.foreground
              border.width: Math.max(1, Style.spaceReal(1))
              opacity: 0.7
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: modeLabel
                anchors.centerIn: parent
                text: root.st ? root.st.mode : ""
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.st ? String(root.st.theme) : "not applied yet"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // ----------------------------------------- the mock libadwaita window
        Rectangle {
          id: mock
          width: parent.width
          height: Style.space(240)
          radius: Style.cornerRadius
          color: root.palColor("window_bg", root.background)
          border.color: root.borderColor
          border.width: Math.max(1, Style.spaceReal(1))
          clip: true

          Column {
            anchors.fill: parent

            // headerbar
            Rectangle {
              width: parent.width
              height: Style.space(40)
              color: root.palColor("headerbar_bg", root.background)

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Rectangle {
                  width: Style.space(11); height: width; radius: width / 2
                  color: root.palColor("accent", root.foreground)
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: "Files"
                  textFormat: Text.PlainText
                  color: root.palColor("fg", root.foreground)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: openLabel.implicitWidth + Style.space(20)
                implicitHeight: openLabel.implicitHeight + Style.space(10)
                radius: Style.cornerRadius
                color: root.palColor("accent", root.foreground)

                Text {
                  id: openLabel
                  anchors.centerIn: parent
                  text: "Open"
                  textFormat: Text.PlainText
                  color: root.palColor("on_accent", root.background)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }

            // body: sidebar + content
            Row {
              width: parent.width
              height: mock.height - Style.space(40)

              Rectangle {
                width: Style.space(150)
                height: parent.height
                color: root.palColor("sidebar_bg", root.background)

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(4)

                  Repeater {
                    model: [
                      { label: "Home", selected: false },
                      { label: "Projects", selected: true },
                      { label: "Downloads", selected: false }
                    ]
                    Rectangle {
                      required property var modelData
                      width: parent.width
                      height: Style.space(26)
                      radius: Style.cornerRadius / 2
                      color: modelData.selected ? root.palColor("accent", root.foreground) : "transparent"

                      Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.label
                        textFormat: Text.PlainText
                        color: parent.modelData.selected
                          ? root.palColor("on_accent", root.background)
                          : root.palColor("fg", root.foreground)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                  }
                }
              }

              Rectangle {
                width: parent.width - Style.space(150)
                height: parent.height
                color: root.palColor("view_bg", root.background)

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(12)
                  spacing: Style.space(8)

                  Text {
                    text: "Every app finally matches."
                    textFormat: Text.PlainText
                    color: root.palColor("fg", root.foreground)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: "GTK4, GTK3 and Qt read this palette."
                    textFormat: Text.PlainText
                    color: root.palColor("muted", root.foreground)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Rectangle {
                    width: parent.width
                    height: Style.space(64)
                    radius: Style.cornerRadius / 2
                    color: root.palColor("surface_bg", root.background)

                    Row {
                      anchors.fill: parent
                      anchors.margins: Style.space(10)
                      spacing: Style.space(10)

                      Rectangle {
                        width: parent.width - toggleMock.width - Style.space(10)
                        height: parent.height
                        radius: Style.cornerRadius / 2
                        color: root.palColor("view_bg", root.background)
                        border.color: root.palColor("accent", root.foreground)
                        border.width: Math.max(1, Style.spaceReal(1))

                        Text {
                          anchors.left: parent.left
                          anchors.leftMargin: Style.space(8)
                          anchors.verticalCenter: parent.verticalCenter
                          text: "search entry"
                          textFormat: Text.PlainText
                          color: root.palColor("muted", root.foreground)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                        }
                      }

                      Rectangle {
                        id: toggleMock
                        width: Style.space(44)
                        height: Style.space(24)
                        radius: height / 2
                        color: root.palColor("accent", root.foreground)
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                          width: parent.height - Style.space(6)
                          height: width
                          radius: width / 2
                          color: root.palColor("on_accent", root.background)
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(3)
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // --------------------------------------------------- swatch strip
        Row {
          spacing: Style.space(8)
          Repeater {
            model: root.pal ? [
              { key: "window_bg", label: "window" },
              { key: "view_bg", label: "view" },
              { key: "headerbar_bg", label: "header" },
              { key: "surface_bg", label: "card" },
              { key: "fg", label: "text" },
              { key: "accent", label: "accent" },
              { key: "on_accent", label: "on-accent" }
            ] : []

            Column {
              required property var modelData
              spacing: Style.space(3)

              Rectangle {
                width: Style.space(74)
                height: Style.space(30)
                radius: Style.cornerRadius / 2
                color: root.palColor(modelData.key, root.background)
                border.color: root.borderColor
                border.width: Math.max(1, Style.spaceReal(1))
              }
              Text {
                text: modelData.label
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.horizontalCenter: parent.horizontalCenter
              }
              Text {
                text: root.palColor(modelData.key, "")
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.horizontalCenter: parent.horizontalCenter
              }
            }
          }
        }

        // ------------------------------------------------------- targets
        Column {
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: {
              if (!root.st) return []
              var rows = []
              if (root.st.files && root.st.files.gtk4)
                rows.push({ label: "GTK4 / libadwaita", detail: root.st.files.gtk4.path + "  (" + root.st.files.gtk4.status + ")" })
              if (root.st.files && root.st.files.gtk3)
                rows.push({ label: "GTK3", detail: root.st.files.gtk3.path + "  (" + root.st.files.gtk3.status + ")" })
              rows.push({ label: "Qt 5 / Qt 6", detail: "follows GTK3 via qgtk3 - applies when an app launches" })
              if (root.st.gsettings && root.st.gsettings.applied)
                rows.push({ label: "color-scheme", detail: root.st.gsettings.color_scheme + "  ·  gtk-theme " + root.st.gsettings.gtk_theme })
              var r = root.st.restarts || {}
              if (r.restarted && r.restarted.length > 0)
                rows.push({ label: "restarted", detail: r.restarted.join(", ") })
              if (r.pending && r.pending.length > 0)
                rows.push({ label: "restart pending", detail: r.pending.join(", ") + " - has open windows; repaints on next launch" })
              return rows
            }

            Item {
              required property var modelData
              width: parent.width
              height: rowLabel.implicitHeight + Style.space(4)

              Text {
                id: rowLabel
                anchors.left: parent.left
                width: Style.space(150)
                text: modelData.label
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
              Text {
                anchors.left: rowLabel.right
                anchors.leftMargin: Style.space(8)
                anchors.right: parent.right
                text: modelData.detail
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.9
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }
            }
          }

          Text {
            visible: root.st === null
            width: parent.width
            text: "Nothing applied yet - press a to bring every GTK and Qt app onto this theme."
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }

        // -------------------------------------------------------- footer
        Text {
          width: parent.width
          text: "a apply now  ·  Esc close"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
