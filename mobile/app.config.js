const fs = require('fs');
const path = require('path');

/**
 * Adds the Apple Developer team ID to the static config in app.json, so the generated iOS project signs
 * automatically. The team ID is deliberately not in git: it comes from the APPLE_TEAM_ID environment variable,
 * or from signing.local.env at the repo root (gitignored; see signing.local.env.example). Without one,
 * everything except building for a real iPhone works unchanged.
 */
function appleTeamId() {
  if (process.env.APPLE_TEAM_ID) return process.env.APPLE_TEAM_ID;
  try {
    const local = fs.readFileSync(path.join(__dirname, '..', 'signing.local.env'), 'utf8');
    return local.match(/^APPLE_TEAM_ID=(\S+)/m)?.[1];
  } catch {
    return undefined;
  }
}

module.exports = ({ config }) => {
  const teamId = appleTeamId();
  if (teamId && teamId !== 'XXXXXXXXXX') config.ios = { ...config.ios, appleTeamId: teamId };
  return config;
};
