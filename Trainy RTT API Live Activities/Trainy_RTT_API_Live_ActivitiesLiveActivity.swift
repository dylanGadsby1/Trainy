//
//  Trainy_RTT_API_Live_ActivitiesLiveActivity.swift
//  Trainy RTT API Live Activities
//
//  Created by Dylan Gadsby on 18/08/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct Trainy_RTT_API_Live_ActivitiesAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct Trainy_RTT_API_Live_ActivitiesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Trainy_RTT_API_Live_ActivitiesAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension Trainy_RTT_API_Live_ActivitiesAttributes {
    fileprivate static var preview: Trainy_RTT_API_Live_ActivitiesAttributes {
        Trainy_RTT_API_Live_ActivitiesAttributes(name: "World")
    }
}

extension Trainy_RTT_API_Live_ActivitiesAttributes.ContentState {
    fileprivate static var smiley: Trainy_RTT_API_Live_ActivitiesAttributes.ContentState {
        Trainy_RTT_API_Live_ActivitiesAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: Trainy_RTT_API_Live_ActivitiesAttributes.ContentState {
         Trainy_RTT_API_Live_ActivitiesAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: Trainy_RTT_API_Live_ActivitiesAttributes.preview) {
   Trainy_RTT_API_Live_ActivitiesLiveActivity()
} contentStates: {
    Trainy_RTT_API_Live_ActivitiesAttributes.ContentState.smiley
    Trainy_RTT_API_Live_ActivitiesAttributes.ContentState.starEyes
}
