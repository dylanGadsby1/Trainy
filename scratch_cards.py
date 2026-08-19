import os

file_path = "/Users/dylangadsby/Trainy/Trainy/ContentView.swift"

with open(file_path, "r") as f:
    content = f.read()

old_timeline = """struct TimelineCard: View {
    @Environment(\\.colorScheme) private var colorScheme
    let journey: TrainJourney

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("LIVE JOURNEY", systemImage: "location.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    .tracking(1)

                HStack {
                    StationTimeView(station: journey.origin)
                    Spacer()
                    StationTimeView(station: journey.intermediate)
                    Spacer()
                    StationTimeView(station: journey.destination)
                }

                GeometryReader { geo in
                    let w = geo.size.width
                    let seg1End = w * 0.45
                    let trainX = w * journey.progressFraction

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdaptiveColor.track.resolve(in: colorScheme))
                            .frame(height: 5)

                        Capsule()
                            .fill(Color.green)
                            .frame(width: seg1End, height: 5)

                        Capsule()
                            .fill(Color.appleBlack.opacity(0.12))
                            .frame(width: w - seg1End, height: 5)
                            .offset(x: seg1End)

                        ForEach(0..<3) { i in
                            let fraction = timelineFractions[i]
                            Circle()
                                .fill(fraction <= CGFloat(journey.progressFraction)
                                      ? Color.green
                                      : AdaptiveColor.dotUnvisited.resolve(in: colorScheme))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.appleBlack.opacity(0.15), lineWidth: 1))
                                .offset(x: w * fraction - 6)
                        }

                        Image(systemName: "tram.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.appleBlack)
                            .clipShape(Circle())
                            .offset(x: trainX - 13, y: -22)
                    }
                }
                .frame(height: 40)

                HStack {
                    Text(journey.origin.code)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(AdaptiveColor.stationCode.resolve(in: colorScheme))
                    Spacer()
                    Text(journey.intermediate.code)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(AdaptiveColor.stationCode.resolve(in: colorScheme))
                    Spacer()
                    Text(journey.destination.code)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(AdaptiveColor.stationCode.resolve(in: colorScheme))
                }
            }
        }
    }
}"""

new_timeline = """struct TimelineCard: View {
    @Environment(\\.colorScheme) private var colorScheme
    let journey: TrainJourney

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("LIVE JOURNEY", systemImage: "location.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    .tracking(1)

                HStack {
                    StationTimeView(station: journey.origin)
                    Spacer()
                    StationTimeView(station: journey.destination)
                }

                GeometryReader { geo in
                    let w = geo.size.width

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdaptiveColor.track.resolve(in: colorScheme))
                            .frame(height: 5)

                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.appleBlack.opacity(0.15), lineWidth: 1))
                            .offset(x: -6)

                        Circle()
                            .fill(AdaptiveColor.dotUnvisited.resolve(in: colorScheme))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.appleBlack.opacity(0.15), lineWidth: 1))
                            .offset(x: w - 6)
                    }
                }
                .frame(height: 12)
                .padding(.vertical, 8)

                HStack {
                    Text(journey.origin.code)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(AdaptiveColor.stationCode.resolve(in: colorScheme))
                    Spacer()
                    Text(journey.destination.code)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(AdaptiveColor.stationCode.resolve(in: colorScheme))
                }
            }
        }
    }
}"""

content = content.replace(old_timeline, new_timeline)

old_arrival = """struct ArrivalContextCard: View {
    @Environment(\\.colorScheme) private var colorScheme
    let journey: TrainJourney

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("PREDICTED PLATFORM", systemImage: "signpost.right.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        .tracking(1)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\\(journey.platform)")
                            .font(.system(size: 56, weight: .black))
                            .foregroundColor(AdaptiveColor.platformTop.resolve(in: colorScheme))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\\(journey.platformProbability)%")
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(.green)
                            Text("Probability")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        }
                    }
                }

                Divider().background(AdaptiveColor.divider.resolve(in: colorScheme))

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "sterlingsign.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow)
                            Text("DELAY REPAY ELIGIBLE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.yellow)
                                .tracking(0.5)
                        }
                        Text("\\(journey.delayMinutes)+ min delay · Avanti West Coast")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    }
                    Spacer()
                    Button(action: {}) {
                        Text("CLAIM NOW")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(Color.appleBlack)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.yellow)
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .background(Color.yellow.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.yellow.opacity(0.20), lineWidth: 1)
                )
            }
        }
    }
}"""

new_arrival = """struct ArrivalContextCard: View {
    @Environment(\\.colorScheme) private var colorScheme
    let journey: TrainJourney

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("PLATFORM", systemImage: "signpost.right.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        .tracking(1)

                    Text("\\(journey.platform)")
                        .font(.system(size: 56, weight: .black))
                        .foregroundColor(AdaptiveColor.platformTop.resolve(in: colorScheme))
                }

                if journey.delayMinutes >= 15 {
                    Divider().background(AdaptiveColor.divider.resolve(in: colorScheme))

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "sterlingsign.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.yellow)
                                Text("DELAY REPAY ELIGIBLE")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.yellow)
                                    .tracking(0.5)
                            }
                            Text("\\(journey.delayMinutes)+ min delay · \\(journey.trainType)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.yellow.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.yellow.opacity(0.20), lineWidth: 1)
                    )
                }
            }
        }
    }
}"""

content = content.replace(old_arrival, new_arrival)


with open(file_path, "w") as f:
    f.write(content)

