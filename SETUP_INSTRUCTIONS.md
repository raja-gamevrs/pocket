# Setup Instructions

To add the LLM.swift dependency to your Xcode project:

1. Open your Xcode project by double-clicking on `pocket.xcodeproj`
2. In Xcode, click on File > Add Packages...
3. In the search field, paste: `https://github.com/eastriverlee/LLM.swift/`
4. Click "Add Package"
5. Make sure "LLM" is selected and click "Add Package"
6. Wait for the package to be resolved and added to your project

## Project Structure

- `ContentView.swift`: Contains the chat interface and model loading logic
- `pocketApp.swift`: Main app entry point
- `Package.swift`: Defines the LLM.swift dependency (reference only)

## Running the App

1. Select your target device/simulator
2. Click the Run button (▶️) in Xcode
3. Wait for the model to download (this may take some time on first launch)
4. Start chatting with the local LLM

## Troubleshooting

If you encounter build errors:
1. Make sure LLM.swift was properly added as a dependency
2. Check that you're using a compatible iOS/macOS version (iOS 16+ / macOS 13+)
3. Clean the build folder (Shift+Cmd+K) and try building again

If the model doesn't load:
1. Check your internet connection (required for initial model download)
2. The app needs sufficient storage space to save the model locally
3. Try restarting the app 