#!/bin/bash
set -euo pipefail
echo "[tb-setup] Starting one-time Thunderbird profile initialization"
export HOME=/home/user
PROFILE_DIR="$HOME/.thunderbird/bytebotprofile.default"
EMAIL=${BYTEBOT_EMAIL_ADDRESS:-}
PROVIDER=${BYTEBOT_EMAIL_PROVIDER:-zoho}
NAME=${BYTEBOT_EMAIL_NAME:-Bot}
MARKER="$HOME/.thunderbird/.bytebot-initialized"
RANDOM_PROFILE_GLOB='*.default*'

# Require explicit IMAP/SMTP settings via environment (no fallbacks)
IMAP_HOST=${BYTEBOT_IMAP_HOST:-}
IMAP_PORT=${BYTEBOT_IMAP_PORT:-}
SMTP_HOST=${BYTEBOT_SMTP_HOST:-}
SMTP_PORT=${BYTEBOT_SMTP_PORT:-}

if [[ -z "$IMAP_HOST" || -z "$SMTP_HOST" ]]; then
  echo "[tb-setup] IMAP/SMTP host env vars not set; skipping profile init (set BYTEBOT_IMAP_HOST / BYTEBOT_SMTP_HOST).";
  exit 0
fi
IMAP_PORT=${IMAP_PORT:-993}
SMTP_PORT=${SMTP_PORT:-465}

echo "[tb-setup] Using EMAIL=$EMAIL IMAP_HOST=$IMAP_HOST IMAP_PORT=$IMAP_PORT SMTP_HOST=$SMTP_HOST SMTP_PORT=$SMTP_PORT"

if [[ -f "$MARKER" ]]; then
  echo "[tb-setup] Already initialized; performing maintenance cleanup."
  mkdir -p "$PROFILE_DIR/Mail/Local Folders" "$PROFILE_DIR/ImapMail/$IMAP_HOST" 2>/dev/null || true
  if [[ -d "$HOME/.thunderbird" ]]; then
    find "$HOME/.thunderbird" -maxdepth 1 -type d -name "$RANDOM_PROFILE_GLOB" \
      ! -name "$(basename "$PROFILE_DIR")" \
      -exec bash -c 'echo "[tb-setup] Removing old profile dir: $0"; rm -rf "$0"' {} \; || true
  fi
  echo "[tb-setup] Rewriting profiles.ini (maintenance)"
  cat > "$HOME/.thunderbird/profiles.ini" <<EOF
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=bytebot-$PROVIDER
IsRelative=1
Path=bytebotprofile.default
Default=1
Locked=1
EOF
  # Build PREF_BLOCK (same as first-run) and always enforce
  PREF_BLOCK=$(cat <<PREFS
user_pref("mail.accountmanager.accounts", "account1");
user_pref("mail.accountmanager.defaultaccount", "account1");
user_pref("mail.accountmanager.localfoldersserver", "server2");
user_pref("mail.account.account1.identities", "id1");
user_pref("mail.account.account1.server", "server1");
user_pref("mail.identity.id1.fullName", "$NAME");
user_pref("mail.identity.id1.useremail", "$EMAIL");
user_pref("mail.identity.id1.smtpServer", "smtp1");
user_pref("mail.identity.id1.valid", true);
user_pref("mail.identity.id1.compose_html", true);
user_pref("mail.identity.id1.reply_to", "");
user_pref("mail.server.server1.type", "imap");
user_pref("mail.server.server1.hostname", "$IMAP_HOST");
user_pref("mail.server.server1.port", $IMAP_PORT);
user_pref("mail.server.server1.userName", "$EMAIL");
user_pref("mail.server.server1.socketType", 3);
user_pref("mail.server.server1.authMethod", 3); // normal password
user_pref("mail.server.server1.login_at_startup", true);
user_pref("mail.server.server1.check_new_mail", true);
user_pref("mail.server.server1.download_on_biff", true);
user_pref("mail.server.server1.offline_download", true);
user_pref("mail.server.server1.directory-rel", "[ProfD]ImapMail/$IMAP_HOST");
user_pref("mail.server.server1.directory", "$PROFILE_DIR/ImapMail/$IMAP_HOST");
user_pref("mail.server.server1.deferGetNewMail", false);
user_pref("mail.server.server1.name", "$EMAIL");
user_pref("mail.check_all_imap_folders_for_new", true);
user_pref("mail.imap.use_status_for_biff", true);
user_pref("mail.server.server2.type", "none");
user_pref("mail.server.server2.hostname", "Local Folders");
user_pref("mail.server.server2.directory-rel", "[ProfD]Mail/Local Folders");
user_pref("mail.server.server2.directory", "$PROFILE_DIR/Mail/Local Folders");
user_pref("mail.server.server2.userName", "nobody");
user_pref("mail.server.server2.name", "Local Folders");
user_pref("mail.server.server2.deferGetNewMail", true);
user_pref("mail.smtpservers", "smtp1");
user_pref("mail.smtp.defaultserver", "smtp1");
user_pref("mail.smtpserver.smtp1.hostname", "$SMTP_HOST");
user_pref("mail.smtpserver.smtp1.port", $SMTP_PORT);
user_pref("mail.smtpserver.smtp1.socketType", 3);
user_pref("mail.smtpserver.smtp1.username", "$EMAIL");
user_pref("mail.smtpserver.smtp1.authMethod", 3); // normal password
user_pref("mail.smtpserver.smtp1.try_ssl", 3); // 3 = SSL/TLS
user_pref("mail.provider.enabled", false);
user_pref("mail.rights.version", 1);
user_pref("mail.shell.checkDefaultClient", false);
user_pref("mailnews.start_page.enabled", false);
user_pref("mailnews.start_page.override_url", "");
user_pref("mailnews.start_page.welcome_url", "");
user_pref("mailnews.start_page_override.mstone", "ignore");
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("datareporting.policy.firstRunURL", "");
user_pref("mail.ui-rdf.version", 1);
user_pref("app.update.enabled", false);
user_pref("extensions.update.enabled", false);
user_pref("mail.accountmanager.promptOnCreateAccount", false);
user_pref("mail.onboarding.enabled", false);
user_pref("mail.new_setup_wizard.enabled", false);
user_pref("mail.new_setup_wizard.seen", true);
user_pref("mail.new_setup_wizard.override", true);
user_pref("mail.accountwizard.skipOnboarding", true);
user_pref("mail.accountwizard.component.enabled", false);
user_pref("mail.useNewAccountUI", false);
user_pref("mail.useNewAccountHub", false);
user_pref("mail.accountmanager.useNewAccountWizard", false);
user_pref("mail.accountmanager.firstuse", false);
user_pref("mailnews.initial_account_creation_finished", true);
user_pref("mail.default_startup_page", 0);
user_pref("mailnews.main_window_disabled_startup_page", false);
user_pref("mail.provider.suppress_dialog_on_startup", true);
user_pref("mail.provider.show_on_first_run", false);
user_pref("mail.startup.enabled", false);
PREFS)
  echo "$PREF_BLOCK" > "$PROFILE_DIR/user.js"
  rm -f "$HOME/.thunderbird/installs.ini" || true
  exit 0
fi

if [[ -z "$EMAIL" ]]; then
  echo "[tb-setup] No email env set; skipping."
  exit 0
fi

mkdir -p "$PROFILE_DIR/Mail/Local Folders" 2>/dev/null || true
mkdir -p "$PROFILE_DIR/ImapMail/$IMAP_HOST" 2>/dev/null || true || true

# Ensure we can write into the mounted profile volume (named docker volume may be root owned)
if [[ ! -w "$HOME/.thunderbird" ]]; then
  echo "[tb-setup] Profile dir not writable; attempting sudo chown"
  sudo chown -R user:user "$HOME/.thunderbird" || echo "[tb-setup] Warning: chown failed"
fi

# Recreate profile subdir in case ownership just changed
mkdir -p "$PROFILE_DIR/Mail/Local Folders"

# Remove any pre-existing random Thunderbird generated profiles so only our deterministic one shows.
if [[ -d "$HOME/.thunderbird" ]]; then
  # Keep Crash Reports / Pending Pings; delete directories matching random default pattern except ours
  find "$HOME/.thunderbird" -maxdepth 1 -type d -name "$RANDOM_PROFILE_GLOB" \
    ! -name "$(basename "$PROFILE_DIR")" \
    -exec bash -c 'echo "[tb-setup] Removing old profile dir: $0"; rm -rf "$0"' {} \; || true
fi


echo "[tb-setup] Writing profiles.ini"
cat > "$HOME/.thunderbird/profiles.ini" <<EOF
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=bytebot-$PROVIDER
IsRelative=1
Path=bytebotprofile.default
Default=1
Locked=1
EOF

echo "[tb-setup] Writing user.js prefs"
PREF_BLOCK=$(cat <<PREFS
user_pref("mail.accountmanager.accounts", "account1");
user_pref("mail.accountmanager.defaultaccount", "account1");
user_pref("mail.accountmanager.localfoldersserver", "server2");
user_pref("mail.account.account1.identities", "id1");
user_pref("mail.account.account1.server", "server1");
user_pref("mail.identity.id1.fullName", "$NAME");
user_pref("mail.identity.id1.useremail", "$EMAIL");
user_pref("mail.identity.id1.smtpServer", "smtp1");
user_pref("mail.identity.id1.valid", true);
user_pref("mail.identity.id1.compose_html", true);
user_pref("mail.identity.id1.reply_to", "");
user_pref("mail.server.server1.type", "imap");
user_pref("mail.server.server1.hostname", "$IMAP_HOST");
user_pref("mail.server.server1.port", $IMAP_PORT);
user_pref("mail.server.server1.userName", "$EMAIL");
user_pref("mail.server.server1.socketType", 3);
user_pref("mail.server.server1.authMethod", 3);
user_pref("mail.server.server1.login_at_startup", true);
user_pref("mail.server.server1.check_new_mail", true);
user_pref("mail.server.server1.download_on_biff", true);
user_pref("mail.server.server1.offline_download", true);
user_pref("mail.server.server1.directory-rel", "[ProfD]ImapMail/$IMAP_HOST");
user_pref("mail.server.server1.directory", "$PROFILE_DIR/ImapMail/$IMAP_HOST");
user_pref("mail.server.server1.deferGetNewMail", false);
user_pref("mail.server.server1.name", "$EMAIL");
user_pref("mail.check_all_imap_folders_for_new", true);
user_pref("mail.imap.use_status_for_biff", true);
user_pref("mail.server.server2.type", "none");
user_pref("mail.server.server2.hostname", "Local Folders");
user_pref("mail.server.server2.directory-rel", "[ProfD]Mail/Local Folders");
user_pref("mail.server.server2.directory", "$PROFILE_DIR/Mail/Local Folders");
user_pref("mail.server.server2.userName", "nobody");
user_pref("mail.server.server2.name", "Local Folders");
user_pref("mail.server.server2.deferGetNewMail", true);
user_pref("mail.smtpservers", "smtp1");
user_pref("mail.smtp.defaultserver", "smtp1");
user_pref("mail.smtpserver.smtp1.hostname", "$SMTP_HOST");
user_pref("mail.smtpserver.smtp1.port", $SMTP_PORT);
user_pref("mail.smtpserver.smtp1.socketType", 3);
user_pref("mail.smtpserver.smtp1.username", "$EMAIL");
user_pref("mail.smtpserver.smtp1.authMethod", 3);
user_pref("mail.smtpserver.smtp1.try_ssl", 3);
// Suppress wizards & first-run noise
user_pref("mail.provider.enabled", false);
user_pref("mail.rights.version", 1);
user_pref("mail.shell.checkDefaultClient", false);
user_pref("mailnews.start_page.enabled", false);
user_pref("mailnews.start_page.override_url", "");
user_pref("mailnews.start_page.welcome_url", "");
user_pref("mailnews.start_page_override.mstone", "ignore");
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("datareporting.policy.firstRunURL", "");
user_pref("mail.ui-rdf.version", 1);
user_pref("app.update.enabled", false);
user_pref("extensions.update.enabled", false);
user_pref("mail.accountmanager.promptOnCreateAccount", false);
user_pref("mail.onboarding.enabled", false);
user_pref("mail.new_setup_wizard.enabled", false);
user_pref("mail.new_setup_wizard.seen", true);
user_pref("mail.new_setup_wizard.override", true);
user_pref("mail.accountwizard.skipOnboarding", true);
user_pref("mail.accountwizard.component.enabled", false);
user_pref("mail.useNewAccountUI", false);
user_pref("mail.useNewAccountHub", false);
user_pref("mail.accountmanager.useNewAccountWizard", false);
user_pref("mail.accountmanager.firstuse", false);
user_pref("mailnews.initial_account_creation_finished", true);
user_pref("mail.default_startup_page", 0);
user_pref("mailnews.main_window_disabled_startup_page", false);
user_pref("mail.provider.suppress_dialog_on_startup", true);
user_pref("mail.provider.show_on_first_run", false);
user_pref("mail.startup.enabled", false);
PREFS)

echo "$PREF_BLOCK" > "$PROFILE_DIR/user.js"

echo "[tb-setup] Priming Thunderbird headless to register account (first run)" 
timeout 12s /usr/lib/thunderbird/thunderbird -headless -profile "$PROFILE_DIR" >/dev/null 2>&1 || true
touch "$MARKER"
echo "[tb-setup] Done. Thunderbird profile prepared & primed. First manual GUI run should skip wizard."
echo "[tb-setup] (Tip) To fully suppress random profile creation in future base images you can set MOZ_NEW_PROFILE=0 before launching Thunderbird if needed."