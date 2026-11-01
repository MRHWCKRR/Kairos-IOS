(Logo)

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
![MIT License][license-shield]

# Kairos

*Everyone has 24 hours a day. Plan your day before it plans you.*

A smart, personalised and practical solution to school/work stressed and last minute tasks.
Kairos helps you plan your day around *your* activities, allowing you to fit *your* tasks into an organised and optimised day.

---

## Key Features

*   **AI Powered Automatic Scheduling:** Saves you time and will maximise time management.

*   **Powerful AI Models:** Intelligent AI Models with optimised prompts for the most uptime and results.

*   **Satisfying and Effective Checklist System:** AI assisted board style checklist, with a satisfying checkmark the feels rewarding to check off.

*   **Board Sharing:** Easily share created boards to others with the inbuilt discovery. Find your friend's schedule and add it to your own Kairos with the click of a button, or find your next fully optimised packed day created by others.

*   **App Customisation:** Customise your Kairos app to your liking with inbuilt themes and custom ones, whether thats on the web, your phone, or tablet.

*   **Automatic Sync:** Move seemlessly across your devices, with auto sync to the cloud, everything is saved, so you can pick back up where you were at anywhere, anytime.

*   **Completely Open Source:** Zero paywalls and full privacy. All source code is hosted right here on GitHub, and all data can be requested at the press of a button. You can even run your own version of Kairos or make your own customisations (see *Try Kairos*)!

---

# Preview

(Photos)

---

# What its made of

* Swift
* SwiftUI

---

# Development setup

Open `Kairos/Kairos.xcodeproj` in Xcode with support for the existing iOS 26.5 deployment target. Firebase Authentication, Firestore, Google Sign-In and Firebase App Check are linked in the project.

See [iOS integration setup](docs/ios-integration-setup.md) for Firebase App Attest registration, simulator debug tokens, signing and the release checklist. AI uses the authenticated Kairos Cloudflare relay; do not add an AI provider key to the app.

## Try Kairos

### 1. Clone and build

```sh
git clone https://github.com/MRHWCKRR/Kairos-IOS.git
cd Kairos-IOS
swift test
open Kairos/Kairos.xcodeproj
```

Choose your signing team and an iPhone or simulator. For simulator AI requests, register the Firebase App Check debug token from the SDK's Xcode console output. Physical devices use App Attest.

### 2. Get The App

Kairos is available on the web, Android and IOS.

The website has more information:
https://kairos-xi-two.vercel.app

Check out their repos!

https://github.com/MRHWCKRR/Kairos

https://github.com/MRHWCKRR/Kairos-Android

**APP DOWNLOADS COMING AFTER GRANT**

---

## Notes

- Bugs will likely exist. If you do encounter one, please make an issue, or reach out to me on Discord: mrhwckrr_v2
- If you want to contribute, send a pull request or dm me on Discord: mrhwckrr_v2

## Acknowledgements

Planify (https://useplanify.com/) for the smooth checkmark and drag and drop inspiration

The lovely people on the Hack Club slack for entertainment

Adriana for the motivation during the start of Kairos development

My mates Matt, Bevan, Neil, Ezaan, Howen and Ethan for supporting me even though Bevan can be a lil harsh I still love him

My parents who supported me during the development with Kairos, especially those long nights where I had my school assignments and tutoring homework

Hackclub Macondo for motivating me to finally start this project, even though I never got to fully participate

ChatGPT, Gemini, Copilot, Claude and Deepseek for helping me solve problems and bugs, as well as teach me new things such as Google log ins and helping me around XCode.


[contributors-shield]: https://img.shields.io/github/contributors/MRHWCKRR/Kairos-IOS.svg?style=for-the-badge
[contributors-url]: https://github.com/MRHWCKRR/Kairos-IOS/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/MRHWCKRR/Kairos-IOS.svg?style=for-the-badge
[forks-url]: https://github.com/MRHWCKRR/Kairos-IOS/network/members
[stars-shield]: https://img.shields.io/github/stars/MRHWCKRR/Kairos-IOS.svg?style=for-the-badge
[stars-url]: https://github.com/MRHWCKRR/Kairos-IOS/stargazers
[issues-shield]: https://img.shields.io/github/issues/MRHWCKRR/Kairos-IOS.svg?style=for-the-badge
[issues-url]: https://github.com/MRHWCKRR/Kairos-IOS/issues
[license-shield]: https://img.shields.io/github/license/MRHWCKRR/Kairos-IOS.svg?style=for-the-badge

