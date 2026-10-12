import SwiftUI

/// Simple test view to verify Darwin API integration
struct DarwinTestView: View {
    @State private var services: [DarwinService] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var stationCRS = "KGX" // King's Cross
    
    var body: some View {
        NavigationStack {
            VStack {
                // Station input
                HStack {
                    Text("Station:")
                        .font(.headline)
                    TextField("CRS Code", text: $stationCRS)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.allCharacters)
                        .frame(width: 100)
                    
                    Button("Fetch") {
                        Task {
                            await loadDepartures()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                
                // Content
                if isLoading {
                    ProgressView("Loading...")
                        .padding()
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Error")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    .padding()
                } else if services.isEmpty {
                    Text("Enter a station code and tap Fetch")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List(services) { service in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(service.destinationName)
                                    .font(.headline)
                                Spacer()
                                Text(service.std ?? "N/A")
                                    .font(.system(.body, design: .monospaced))
                                    .bold()
                            }
                            
                            HStack {
                                if let op = service.operator {
                                    Text(op)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if let platform = service.platform {
                                    Text("Platform \(platform)")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            if let etd = service.etd, etd != "On time" {
                                Text("Expected: \(etd)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            
                            if service.isCancelled == true {
                                Text("CANCELLED")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Darwin API Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func loadDepartures() async {
        guard !stationCRS.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        services = []
        
        do {
            let board = try await DarwinService.shared.departures(from: stationCRS, numRows: 10)
            
            // Check if we got services
            if let trainServices = board.trainServices {
                services = trainServices
            } else {
                errorMessage = "No train services found"
            }
            
            print("✅ Darwin API Success!")
            print("Station: \(board.locationName ?? "Unknown")")
            print("Services: \(services.count)")
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Darwin API Error: \(error)")
        }
        
        isLoading = false
    }
}

#Preview {
    DarwinTestView()
}
