import os

file_path = "/Users/dylangadsby/Trainy/Trainy/ContentView.swift"

with open(file_path, "r") as f:
    content = f.read()

# 1. TrainJourney & mockJourney
old_models = """struct TrainJourney {
    let origin: TrainStation
    let intermediate: TrainStation
    let destination: TrainStation
    let scheduledDeparture: String
    let predictedArrival: String
    let actualArrival: String
    let delayMinutes: Int
    let confidence: Int
    let platform: Int
    let platformProbability: Int
    let trainUnit: String
    let trainType: String
    let trainCars: Int
    let inboundLateMinutes: Int
    let connectionRisk: String
    let connectionService: String
    let transferMinutes: Int
    let congestionAvgDelay: Int
    let progressFraction: Double
}

let mockJourney = TrainJourney(
    origin: TrainStation(code: "LPY", name: "Long Preston", scheduled: "11:00", actual: "11:00"),
    intermediate: TrainStation(code: "RUG", name: "Rugby", scheduled: "11:52", actual: "11:58"),
    destination: TrainStation(code: "EUS", name: "London Euston", scheduled: "12:45", actual: "13:01"),
    scheduledDeparture: "11:00 LPY-EUS",
    predictedArrival: "13:01",
    actualArrival: "12:45",
    delayMinutes: 16,
    confidence: 89,
    platform: 12,
    platformProbability: 98,
    trainUnit: "390151",
    trainType: "AVANTI PENDOLINO",
    trainCars: 9,
    inboundLateMinutes: 14,
    connectionRisk: "LOW RISK",
    connectionService: "14:51 Southeastern Service",
    transferMinutes: 5,
    congestionAvgDelay: 11,
    progressFraction: 0.72
)"""

new_models = """struct TrainJourney {
    let origin: TrainStation
    let destination: TrainStation
    let scheduledDeparture: String
    let predictedArrival: String
    let actualArrival: String
    let delayMinutes: Int
    let platform: String
    let trainType: String
}

let mockJourney = TrainJourney(
    origin: TrainStation(code: "LPY", name: "Long Preston", scheduled: "11:00", actual: "11:00"),
    destination: TrainStation(code: "EUS", name: "London Euston", scheduled: "12:45", actual: "13:01"),
    scheduledDeparture: "11:00",
    predictedArrival: "13:01",
    actualArrival: "12:45",
    delayMinutes: 0,
    platform: "12",
    trainType: "AVANTI PENDOLINO"
)"""

content = content.replace(old_models, new_models)

# 2. StatusHeaderCard
old_status_text = """                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.appBlue)
                            Text("\\(journey.delayMinutes)M DELAY PREDICTED")
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(.appBlue)
                        }
                        Text("BASED ON INBOUND EQUIPMENT (\\(journey.scheduledDeparture))")"""

new_status_text = """                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(journey.delayMinutes > 0 ? .red : .green)
                            Text(journey.delayMinutes > 0 ? "\\(journey.delayMinutes)M DELAY PREDICTED" : "ON TIME")
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(journey.delayMinutes > 0 ? .red : .green)
                        }
                        Text("SCHEDULED DEPARTURE: \\(journey.scheduledDeparture)")"""

content = content.replace(old_status_text, new_status_text)

# 3. toTrainJourney
old_extension = """extension RTTAPIService {
    func toTrainJourney() -> TrainJourney {
        let originCode = userSearchOriginCRS ?? (originCRS.isEmpty ? "UNK" : originCRS)
        let destCode = userSearchDestinationCRS ?? (destinationCRS.isEmpty ? "UNK" : destinationCRS)
        
        let originStation = TrainStation(code: originCode, name: originCode, scheduled: scheduledDeparture, actual: realtimeDeparture)
        let destStation = TrainStation(code: destCode, name: destCode, scheduled: userSearchDestinationArrivalTime ?? scheduledDeparture, actual: userSearchDestinationArrivalTime ?? scheduledDeparture)
        let intermediateStation = TrainStation(code: "INT", name: "Intermediate", scheduled: "--:--", actual: "--:--")
        
        let parsedPlatform = Int(platform) ?? Int.random(in: 1...12)
        
        return TrainJourney(
            origin: originStation,
            intermediate: intermediateStation,
            destination: destStation,
            scheduledDeparture: "\\(scheduledDeparture) \\(originCode)-\\(destCode)",
            predictedArrival: userSearchDestinationArrivalTime ?? scheduledDeparture,
            actualArrival: userSearchDestinationArrivalTime ?? scheduledDeparture,
            delayMinutes: delayMinutes,
            confidence: Int.random(in: 80...99),
            platform: parsedPlatform,
            platformProbability: Int.random(in: 75...99),
            trainUnit: ["390151", "802001", "350101", "158701"].randomElement()!,
            trainType: atocName ?? "Unknown Service",
            trainCars: [4, 5, 8, 9, 11].randomElement()!,
            inboundLateMinutes: max(0, delayMinutes - Int.random(in: 1...5)),
            connectionRisk: delayMinutes > 5 ? "ELEVATED RISK" : "LOW RISK",
            connectionService: "Various Connections",
            transferMinutes: Int.random(in: 3...15),
            congestionAvgDelay: Int.random(in: 2...12),
            progressFraction: 0.15
        )
    }
}"""

new_extension = """extension RTTAPIService {
    func toTrainJourney() -> TrainJourney {
        let originCode = userSearchOriginCRS ?? (originCRS.isEmpty ? "UNK" : originCRS)
        let destCode = userSearchDestinationCRS ?? (destinationCRS.isEmpty ? "UNK" : destinationCRS)
        
        let originStation = TrainStation(code: originCode, name: originCode, scheduled: scheduledDeparture, actual: realtimeDeparture)
        let destStation = TrainStation(code: destCode, name: destCode, scheduled: userSearchDestinationArrivalTime ?? scheduledDeparture, actual: userSearchDestinationArrivalTime ?? scheduledDeparture)
        
        return TrainJourney(
            origin: originStation,
            destination: destStation,
            scheduledDeparture: "\\(scheduledDeparture) \\(originCode)-\\(destCode)",
            predictedArrival: userSearchDestinationArrivalTime ?? scheduledDeparture,
            actualArrival: userSearchDestinationArrivalTime ?? scheduledDeparture,
            delayMinutes: delayMinutes,
            platform: platform,
            trainType: atocName ?? "Unknown Service"
        )
    }
}"""

content = content.replace(old_extension, new_extension)


# 4. Header Row in JourneyDashboardView
old_header = """                    // Header row
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LPY → EUS")
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                            Text("Tue 29 Jul · Avanti West Coast")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        }"""

new_header = """                    // Header row
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\\(journey.origin.code) → \\(journey.destination.code)")
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                            Text(journey.trainType)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        }"""

content = content.replace(old_header, new_header)


# 5. JourneyDashboardView cards
old_cards = """                    StatusHeaderCard(journey: journey)
                    TimelineCard(journey: journey)

                    HStack {
                        Text("PREDICTIVE INTELLIGENCE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                            .tracking(1.5)
                        Spacer()
                    }

                    CongestionCard(journey: journey)
                    RollingStockCard(journey: journey)
                    ConnectionRiskCard(journey: journey)

                    HStack {
                        Text("ARRIVAL CONTEXT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                            .tracking(1.5)
                        Spacer()
                    }

                    ArrivalContextCard(journey: journey)"""

new_cards = """                    StatusHeaderCard(journey: journey)
                    TimelineCard(journey: journey)

                    HStack {
                        Text("ARRIVAL CONTEXT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                            .tracking(1.5)
                        Spacer()
                    }

                    ArrivalContextCard(journey: journey)"""

content = content.replace(old_cards, new_cards)


with open(file_path, "w") as f:
    f.write(content)

