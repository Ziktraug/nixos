// Zen Browser Configuration
user_pref("zen.urlbar.replace-newtab", false);

// Restore previous session on startup
user_pref("browser.startup.page", 3);

// Session preservation - Don't clear cookies/sessions on shutdown
user_pref("privacy.sanitize.sanitizeOnShutdown", false);
user_pref("privacy.clearOnShutdown.cookies", false);
user_pref("privacy.clearOnShutdown.sessions", false);
user_pref("privacy.clearOnShutdown.offlineApps", false);

// Prevent Firefox Sync from overriding session/privacy settings
// These settings disable sync for specific preferences so user.js values persist
user_pref("services.sync.prefs.sync.browser.startup.page", false);
user_pref("services.sync.prefs.sync.privacy.sanitize.sanitizeOnShutdown", false);
user_pref("services.sync.prefs.sync.privacy.clearOnShutdown.cookies", false);
user_pref("services.sync.prefs.sync.privacy.clearOnShutdown.sessions", false);
user_pref("services.sync.prefs.sync.privacy.clearOnShutdown.offlineApps", false);

// Disable split view feature
user_pref("zen.splitView.enable-tab-drop", false);
user_pref("zen.splitView.min-resize-width", 0);
user_pref("zen.splitView.rearrange-hover-size", 0);
