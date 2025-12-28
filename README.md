# n8n Device Relay

This repository provides a complete setup for relaying events from your Android device (SMS, incoming calls, app notifications, Wi-Fi connections) to your n8n instance, and subsequently to other services like Telegram.

It includes example configurations for **n8n**, **MacroDroid**, and **Tasker**, allowing you to easily set up a powerful automation workflow.

## Features

-   **Relay SMS**: Forward incoming SMS messages to n8n.
-   **Relay Calls**: Notify n8n about incoming calls.
-   **Relay Notifications**: Send app notifications to n8n.
-   **Relay Wi-Fi Events**: Trigger workflows when your device connects to Wi-Fi.
-   **Secure**: Uses a custom `x-n8n-device-relay` header and secret tokens to authenticate requests from your device.
-   **Flexible Configuration**: Define rules, templates, and endpoints in a single JSON config within n8n.

## Prerequisites

-   An instance of [n8n](https://n8n.io/) (self-hosted or cloud).
-   At leaset one Android device.
-   [MacroDroid](https://play.google.com/store/apps/details?id=com.arlosoft.macrodroid) OR [Tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskerm) installed on your Android device.
-   A Telegram Bot.

## Setup Guide

### 1. n8n Setup

1.  **Import Workflow**:
    -   Go to your n8n dashboard.
    -   Import the workflow file located at `assets/workflows/device-relay-telegram.workflow.json`.
    -   This workflow handles the incoming webhooks and processes them based on your configuration.

2.  **Create Configuration**:
    -   The workflow relies on a `Config` node that contains your specific settings (tokens, API keys, rules).
    -   Open the `assets/workflow-configs/example_for_oneself.json` file.
    -   Copy its content.
    -   In the n8n workflow, locate the `Config` node (usually a "Code" or "Set" node, or specifically designed to hold this JSON). *Note: Ensure the node where you paste this config matches the workflow's expectation.*
    -   **Update the Config**:
        -   `tokens`: Define a name (e.g., "myphone") and a secure secret key (e.g., "my-secret-token"). You will need this key for your mobile app.
        -   `recipients.me.vars`: Insert your Telegram Bot Token and Chat ID.
        -   Review the `rules`, `endpoints`, and `templates` to customize behavior if needed.

### 2. Mobile App Setup

Choose either **MacroDroid** or **Tasker**.

#### Option A: MacroDroid

1.  **Transfer Files**: Copy the `.macro` files from `assets/macrodroid/` to your phone.
2.  **Import Macros**:
    -   Open MacroDroid.
    -   Import the macros:
        -   `SMS_to_n8n.macro`
        -   `Call_received_to_n8n.macro`
        -   `App_notification_to_n8n.macro`
        -   `Wi-Fi_connected_to_n8n.macro`
3.  **Configure Webhook**:
    -   Open each macro.
    -   Locate the "HTTP Request" (or Webhook) action.
    -   **URL**: Update the URL to point to your n8n webhook (e.g., `https://your-n8n-instance.com/webhook/device-relay`).
    -   **Headers**: Ensure the `x-n8n-device-relay` header is set to the secret key you defined in the n8n config (e.g., "my-secret-token").
    -   **Device ID**: Ensure the payload or query parameters include the device ID you defined (e.g., "myphone").

#### Option B: Tasker

1.  **Transfer Files**: Copy the `.prf.xml` (or `.prf`) files from `assets/tasker/` to your phone.
2.  **Import Profiles**:
    -   Open Tasker.
    -   Long-press on the "Profiles" tab and select "Import".
    -   Import the profiles:
        -   `all_sms_to_n8n.prf`
        -   `all_calls_to_n8n.prf`
        -   `all_notifications_to_n8n.prf`
        -   `all_wifi_to_n8n.prf`
3.  **Configure Task**:
    -   These profiles likely link to a Task that performs the HTTP request.
    -   Open the linked Task.
    -   **HTTP Request**: Update the URL to your n8n webhook.
    -   **Headers**: Set `x-n8n-device-relay: <YOUR_SECRET_KEY>`.

## Configuration Structure

The n8n configuration JSON (`example_for_oneself.json`) is structured as follows:

-   **`tokens`**: Array of valid device tokens.
    -   `name`: Identifier for the device (sent in webhook payload).
    -   `key`: Secret key (sent in `x-n8n-device-relay` header).
-   **`recipients`**: Defines users and their specific variables (like API keys).
    -   `vars`: Variables like `botToken`, `tgChatId`.
    -   `rules`: Logic mapping events (`sms_received`, `call_received`, etc.) to actions.
-   **`endpoints`**: Definitions of external API endpoints (e.g., Telegram `sendMessage`).
-   **`templates`**: Message templates for different events and languages.

## Security

Security is established via:
1.  **HTTPS**: Always use HTTPS for your n8n instance.
2.  **Header Authentication**: The workflow checks for the `x-n8n-device-relay` header. If it doesn't match the key defined in your config for the specific device ID, the request is rejected.

## Repository Structure

-   `assets/workflows/`: Contains the main n8n workflow file.
-   `assets/workflow-configs/`: Contains example JSON configurations for the n8n workflow.
-   `assets/macrodroid/`: Contains MacroDroid export files.
-   `assets/tasker/`: Contains Tasker profile export files.
