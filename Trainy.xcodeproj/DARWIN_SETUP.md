# Darwin API Integration Guide

## ✅ Setup Complete!

Your app is now configured to use the **National Rail Live Departure Boards JSON API** directly (no Huxley2 needed).

## 📋 Next Steps

### 1. Add Your API Key

Open `Secrets.swift` and replace the placeholder with your actual API key:

```swift
static let railDataKey = "YOUR_ACTUAL_API_KEY_HERE"
```

### 2. Add Secrets.swift to .gitignore

Create a `.gitignore` file in your project root (if you don't have one):

```
# Secrets
Secrets.swift

# Xcode
*.xcuserdata
*.xcworkspace/xcuserdata/
DerivedData/
.DS_Store
```

### 3. Test the Integration

You can use the `DarwinTestView` I created to verify everything works:

**Option A: Run it in a Preview**
- Open `DarwinTestView.swift` in Xcode
- Click the Preview button
- Enter a station code (e.g., "KGX" for King's Cross)
- Tap "Fetch"

**Option B: Add it to your app temporarily**
- In `ContentView.swift`, add a test tab:
```swift
Tab("Darwin Test", systemImage: "hammer", value: 3) {
    DarwinTestView()
}
```

### 4. Verify in Console

When you run the test, check Xcode's console for:
- ✅ Success message: "Darwin API Success!"
- 📊 Raw JSON response (in debug builds)
- ❌ Any error messages

## 🔧 API Endpoints Now Available

Your `DarwinService.shared` now supports:

```swift
// Get departures from a station
let board = try await DarwinService.shared.departures(from: "EUS")

// Get departures to a specific destination
let board = try await DarwinService.shared.departures(
    from: "KGX", 
    numRows: 10,
    filterCrs: "EDB" // Edinburgh
)

// Get arrivals at a station
let board = try await DarwinService.shared.arrivals(at: "PAD")

// Get next trains between two stations
let board = try await DarwinService.shared.next(from: "MAN", to: "LIV")

// Get fastest trains between two stations
let board = try await DarwinService.shared.fastest(from: "LBG", to: "VIC")

// Get service details
let details = try await DarwinService.shared.serviceDetails(serviceId: "...")
```

## 🎯 Example: Access Train Data

```swift
let board = try await DarwinService.shared.departures(from: "KGX")

if let services = board.trainServices {
    for service in services {
        print("To: \(service.destinationName)")
        print("Departs: \(service.std ?? "N/A")")
        print("Platform: \(service.platform ?? "TBC")")
        print("Status: \(service.status.displayText)")
        print("Operator: \(service.operator ?? "Unknown")")
        
        if service.isCancelled == true {
            print("⚠️ CANCELLED")
        }
    }
}
```

## 📱 Integration with Your Existing App

### Replace RTT in DeparturesBoardView (Optional)

If you want to use Darwin instead of RTT for the departures board, update `ContentView.swift`:

```swift
// In DeparturesBoardView.loadData()
private func loadData() async {
    isLoading = true
    errorMessage = nil
    do {
        // Change from RTTService to DarwinService
        let board = try await DarwinService.shared.departures(from: crs)
        
        // Map Darwin services to your existing model if needed
        // OR update your UI to use DarwinService directly
        
    } catch {
        errorMessage = error.localizedDescription
    }
    isLoading = false
}
```

## ⚠️ Important Notes

1. **Date Format**: The API uses `yyyyMMdd` format (e.g., `20220120`). The service automatically uses today's date.

2. **CRS Codes**: Must be uppercase 3-letter codes (e.g., "KGX", "EUS", "PAD")

3. **Rate Limits**: Be mindful of API rate limits. Consider caching responses if needed.

4. **JSON Structure**: The actual JSON response from National Rail might differ slightly from Huxley2. If you get decoding errors, check the console output to see the actual structure and update the models accordingly.

5. **Error Handling**: The service now properly handles:
   - 401/403 (Invalid API key)
   - 429 (Rate limit exceeded)
   - Network errors
   - JSON decoding errors

## 🐛 Troubleshooting

### "Invalid Access Token" Error
- Make sure your API key is correct in `Secrets.swift`
- Verify the key is active on the Rail Data Marketplace

### No Data Returned
- Check that the station CRS code is valid
- Verify the date format is correct (automatic, but check console logs)
- Some stations may have no services at certain times

### JSON Decoding Errors
- Check the console for the raw JSON response
- The model structs may need adjustment based on actual API response
- Contact me with the console output and I'll help fix the models

## 🎉 You're All Set!

Once you've added your API key and tested it, you're ready to use official National Rail data in your app. No more Huxley2 dependency!
