import ActivityKit
import WidgetKit
import SwiftUI

struct Trainy_RTT_API_Live_ActivitiesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainyActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            LiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "tram.fill")
                        Text(context.attributes.originCRS)
                            .font(.headline)
                    }
                    .foregroundColor(.primary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.destinationCRS)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.expectedDeparture)
                        .font(.body)
                        .bold()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.isCancelled {
                            Text("Cancelled")
                                .foregroundColor(.red)
                                .bold()
                        } else if context.state.delayMinutes > 0 {
                            Text("Delayed \(context.state.delayMinutes)m")
                                .foregroundColor(.red)
                                .bold()
                        } else {
                            Text("On Time")
                                .foregroundColor(.green)
                                .bold()
                        }
                        Spacer()
                        Text("Plat \(context.state.platform.isEmpty ? "TBC" : context.state.platform)")
                            .font(.subheadline)
                    }
                }
            } compactLeading: {
                Text("\(context.attributes.originCRS)")
                    .font(.caption)
                    .bold()
            } compactTrailing: {
                Text(context.state.expectedDeparture)
                    .font(.caption)
                    .foregroundColor(context.state.isCancelled || context.state.delayMinutes > 0 ? .red : .green)
            } minimal: {
                Image(systemName: "tram.fill")
                    .foregroundColor(context.state.isCancelled || context.state.delayMinutes > 0 ? .red : .green)
            }
            .widgetURL(URL(string: "trainy://train/\(context.attributes.trainId)"))
            .keylineTint(Color.cyan)
        }
    }
}

struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<TrainyActivityAttributes>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.attributes.operatorCode)
                    .font(.caption)
                    .bold()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(4)
                
                Spacer()
                
                Text(context.state.expectedDeparture)
                    .font(.headline)
            }
            
            HStack {
                Text(context.attributes.originName)
                Image(systemName: "arrow.right")
                Text(context.attributes.destinationName)
            }
            .font(.subheadline)
            .bold()
            
            HStack {
                if context.state.isCancelled {
                    Text("Cancelled")
                        .foregroundColor(.red)
                        .bold()
                } else if context.state.delayMinutes > 0 {
                    Text("\(context.state.delayMinutes)m late")
                        .foregroundColor(.red)
                        .bold()
                } else {
                    Text("On Time")
                        .foregroundColor(.green)
                        .bold()
                }
                Spacer()
                Text("Platform \(context.state.platform.isEmpty ? "TBC" : context.state.platform)")
                    .foregroundColor(.white.opacity(0.8))
            }
            .font(.caption)
        }
        .padding()
        .activityBackgroundTint(Color(red: 0.1, green: 0.1, blue: 0.15))
        .activitySystemActionForegroundColor(Color.white)
    }
}
