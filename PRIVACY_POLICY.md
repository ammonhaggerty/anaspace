# Privacy Policy

**Last Updated: February 20, 2026**

Anaspace ("the App") is committed to protecting your privacy. This Privacy Policy explains what information the App collects, how it is used, and the choices you have.

## Information We Collect

### Microphone Audio

The App accesses your device microphone to identify music playing nearby (via Apple ShazamKit) and to transcribe spoken words (via Apple Speech Recognition). Audio is processed on-device and is not recorded or stored. Only the resulting music match or text transcript is used.

### Location Data

The App accesses your approximate location (when in use) to provide location-relevant cultural context. Your location is reverse-geocoded into a general area (city, state, country) and is not tracked in the background.

### Speech Recognition

When you use the hold-to-observe feature, spoken audio is transcribed on-device using Apple's Speech Recognition framework. The resulting text transcript may be sent to our AI service to generate cultural context.

### Observation Data

When you make an observation, the App sends the following to Anthropic's Claude API to generate cultural context:

- Music identification results (song title, artist)
- Speech transcripts
- Your general location (city-level)
- The subject, place, and year you are exploring

### Apple Music

The App uses Apple MusicKit to search the Apple Music catalog and play song previews. The App does not access your personal Apple Music library.

### Local Storage

The App stores your recent observation history (up to 12 entries) and user preferences (such as autoplay settings) locally on your device. This data is not transmitted to any server.

## Third-Party Services

The App uses the following third-party services, each governed by their own privacy policies:

- **Anthropic (Claude API)** — Processes observation context to generate cultural information. [Privacy Policy](https://www.anthropic.com/privacy)
- **Mapbox** — Provides interactive map display. [Privacy Policy](https://www.mapbox.com/legal/privacy)
- **Apple Services** — ShazamKit, Speech Recognition, and MusicKit are Apple frameworks subject to [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

## Information We Do Not Collect

- We do not create user accounts or collect personal identifiers (name, email, phone number).
- We do not use analytics, advertising, or tracking SDKs.
- We do not sell, share, or rent your data to third parties.
- We do not access your contacts, photos, calendar, or health data.
- We do not track your location in the background.

## Data Retention

Observation history is stored locally on your device and can be cleared by deleting the App. Data sent to Anthropic's Claude API is processed in real time and is subject to [Anthropic's data retention policies](https://www.anthropic.com/privacy).

## Children's Privacy

The App is not directed at children under the age of 13 and does not knowingly collect personal information from children.

## Changes to This Policy

We may update this Privacy Policy from time to time. Any changes will be reflected by updating the "Last Updated" date above.

## Contact

If you have questions about this Privacy Policy, please open an issue on our [GitHub repository](https://github.com/AHaggerty/anaspace).
