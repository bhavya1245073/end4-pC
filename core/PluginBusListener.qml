// Declarative subscription to a PluginBus topic, unsubscribed automatically when the
// widget goes away.
//
//     PluginBusListener {
//         topic: "wallpaper:changed"
//         onReceived: payload => root.tint = payload.dominantColor
//     }
//
// Prefer this over PluginBus.on(): a handler registered by hand outlives the object that
// created it unless every destruction path remembers to call off(), and a desktop widget
// is created and destroyed every time its plugin is toggled.
//
// `topic` may end in "*" to match by prefix ("notifications:*"). Changing `topic` at
// runtime moves the subscription.

import QtQuick
import qs.core

QtObject {
    id: root

    property string topic: ""
    property bool enabled: true

    // (payload, topic) - the topic is passed too, which is what makes a wildcard
    // subscription useful.
    signal received(var payload, string topic)

    // Replays the retained value, if any, as soon as the subscription starts. Off by
    // default: a listener that reacts to an event should not fire for one that already
    // happened, but a listener mirroring state usually wants the current value.
    property bool replayRetained: false

    property int __token: 0

    function __subscribe(): void {
        root.__unsubscribe();
        if (!root.enabled || !root.topic)
            return;
        root.__token = PluginBus.on(root.topic, (payload, name) => root.received(payload, name));
        if (root.replayRetained && PluginBus.has(root.topic))
            root.received(PluginBus.value(root.topic, undefined), root.topic);
    }

    function __unsubscribe(): void {
        if (root.__token) {
            PluginBus.off(root.__token);
            root.__token = 0;
        }
    }

    onTopicChanged: root.__subscribe()
    onEnabledChanged: root.__subscribe()
    Component.onCompleted: root.__subscribe()
    Component.onDestruction: root.__unsubscribe()
}
