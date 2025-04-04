# Pocket LLM Chat

A simple chat application that uses local LLM models downloaded from Hugging Face for inference. This demo uses the LLM.swift package to leverage local language models on iOS/macOS devices.

## Features

- Downloads and caches LLM models from Hugging Face
- Local inference (no data sent to cloud)
- Simple chat interface with streaming responses
- Completely offline once model is downloaded

## Setup

1. Open the project in Xcode
2. Add the dependency: https://github.com/eastriverlee/LLM.swift/ (via Swift Package Manager)
3. Build and run the app

## Usage

The app will automatically download the model on first launch. Once the model is downloaded, you can start chatting with the AI assistant.

## Model Information

By default, this app uses TinyLlama-1.1B-Chat-v1.0 with Q2_K quantization, which is small enough for testing but still provides reasonable responses. You can modify the code to use other GGUF-compatible models from Hugging Face.

## Requirements

- iOS 16.0+ / macOS 13.0+
- Xcode 14.0+
- Swift 5.7+ 