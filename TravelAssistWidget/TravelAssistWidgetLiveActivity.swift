//
//  TravelAssistWidgetLiveActivity.swift
//  TravelAssistWidget
//
//  Created by Rajesh Mani on 09/03/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct TravelAssistWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var etaMinutes: Int
        var statusText: String
        var progress: Double
        var distanceText: String
    }

    var name: String
}

struct TravelAssistWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TravelAssistWidgetAttributes.self) { context in
            LiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("ETA \(context.state.etaMinutes)m")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "car.side.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.statusText)
                            .font(.subheadline)
                            .lineLimit(1)
                        ProgressView(value: context.state.progress)
                            .progressViewStyle(.linear)
                    }
                }
            } compactLeading: {
                Text("\(context.state.etaMinutes)m")
                    .font(.caption2)
            } compactTrailing: {
                Image(systemName: "car.side.fill")
                    .foregroundStyle(.orange)
            } minimal: {
                Image(systemName: "car.side.fill")
                    .foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
    }
}

private struct LiveActivityLockScreenView: View {
    let state: TravelAssistWidgetAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                (Text("Arriving in ").foregroundStyle(.white.opacity(0.9))
                + Text("\(max(state.etaMinutes, 0)) mins").foregroundStyle(.orange))
                    .font(.footnote)
                    .lineLimit(1)

                Text(state.statusText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: min(max(state.progress, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(.orange)
                    Text(state.distanceText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(.orange.opacity(0.20))
                    .frame(width: 48, height: 48)
                Image(systemName: "car.side.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.95), Color.gray.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
