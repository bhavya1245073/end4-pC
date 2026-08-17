import qs.modules.common
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    // Static children: `GroupedList { RowA {} RowB {} }`.
    default property list<Item> items

    // Dynamic rows: `GroupedList { model: SomeRegistry.all; delegate: Component { ... } }`.
    //
    // Both exist because a Repeater cannot fill `items`. Declared children go into a
    // `list<Item>` at compile time; a Repeater builds its children at runtime and parents them to
    // itself, so `items` ends up holding the Repeater - one Item, of zero height. The list then
    // reported `implicitHeight: 0` while drawing full-height rows outside its own bounds, which is
    // why the desktop menu's rows spilled past the bottom of its card with no background under
    // them. Nothing warned: every part of that is legal.
    property var model: undefined
    property Component delegate: null

    readonly property bool dynamic: root.model !== undefined && root.delegate !== null

    property real bigRadius: Appearance.rounding.normal
    property real smallRadius: Appearance.rounding.unsharpenmore
    property color bgcolor: Appearance.colors.colLayer1
    property real itemVerticalPadding: 24
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: root.dynamic ? 0 : root.items.length
            delegate: Rectangle {
                required property int index
                readonly property bool isFirst: index === 0
                readonly property bool isLast: index === root.items.length - 1
                Layout.fillWidth: true
                implicitHeight: (root.items[index]?.implicitHeight ?? 0) + root.itemVerticalPadding
                color: root.bgcolor
                topLeftRadius:     isFirst ? root.bigRadius : root.smallRadius
                topRightRadius:    isFirst ? root.bigRadius : root.smallRadius
                bottomLeftRadius:  isLast  ? root.bigRadius : root.smallRadius
                bottomRightRadius: isLast  ? root.bigRadius : root.smallRadius

                Component.onCompleted: {
                    const child = root.items[index]
                    if (child) {
                        child.parent = contentArea
                        child.Layout.fillWidth = true
                    }
                }

                ColumnLayout {
                    id: contentArea
                    anchors { fill: parent; margins: 8 }
                    spacing: 0
                }
            }
        }

        Repeater {
            id: dynamicRows
            model: root.dynamic ? root.model : 0
            delegate: Rectangle {
                id: wrapper
                required property var modelData
                required property int index

                readonly property bool isFirst: index === 0
                readonly property bool isLast: index === dynamicRows.count - 1

                Layout.fillWidth: true
                implicitHeight: (wrapper.content?.implicitHeight ?? 0) + root.itemVerticalPadding
                color: root.bgcolor
                topLeftRadius:     isFirst ? root.bigRadius : root.smallRadius
                topRightRadius:    isFirst ? root.bigRadius : root.smallRadius
                bottomLeftRadius:  isLast  ? root.bigRadius : root.smallRadius
                bottomRightRadius: isLast  ? root.bigRadius : root.smallRadius

                // Built imperatively so `modelData` and `index` can be handed over as initial
                // properties. A Loader cannot do that - it has no way to inject into the component
                // it creates - and a delegate declaring them `required`, which is the correct way
                // to write one, fails to construct without them.
                property Item content: null
                Component.onCompleted: {
                    wrapper.content = root.delegate.createObject(slot, {
                        modelData: wrapper.modelData,
                        index: wrapper.index
                    });
                    if (wrapper.content)
                        wrapper.content.Layout.fillWidth = true;
                }

                ColumnLayout {
                    id: slot
                    anchors { fill: parent; margins: 8 }
                    spacing: 0
                }
            }
        }
    }
}