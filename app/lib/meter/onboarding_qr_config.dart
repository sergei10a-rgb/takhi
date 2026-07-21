// SPDX-License-Identifier: AGPL-3.0-or-later

/// Where the "Тахь тат" QR (spec §7.4 step 6, §10 onboarding loop) points a
/// scanning phone. The real distribution channel (own domain vs. GitHub
/// Releases vs. F-Droid) is an open protocol question (spec §16.4/§16.5) —
/// this is the MVP default, easy to swap in one place once decided.
const String kTakhiAppDownloadUrl =
    'https://github.com/takhi-app/takhi/releases/latest';
