// The two apps this Worker serves. Everything here is public
// information (bundle IDs, product IDs, feed URLs).

export const APPS = {
  baseball: {
    name: 'The Daily Box Score',
    bundleId: 'com.omcollective.dailyboxscore',
    passProductIds: [
      'com.omcollective.dailyboxscore.archivepass.yearly',
      'com.omcollective.dailyboxscore.archivepass.lifetime',
    ],
    configUrl: 'https://www.toolstem.com/daily-box-score/feed/app_config.json',
    editionsUrl: 'https://www.toolstem.com/daily-box-score/feed/editions.json',
    pdfUrl: (date) => `https://www.toolstem.com/daily-box-score/pdfs/boxscores_${date}.pdf`,
    fileName: (date) => `daily_box_score_${date}.pdf`,
    // Current baseball comes from the MLB Stats API, so the MLB kill
    // switch also stops baseball delivery.
    mlb: true,
  },
  football: {
    name: 'Football Box Scores',
    bundleId: 'com.omcollective.footballboxscores',
    passProductIds: [
      'com.omcollective.footballboxscores.archivepass.yearly',
      'com.omcollective.footballboxscores.archivepass.lifetime',
    ],
    configUrl: 'https://www.toolstem.com/football-box-scores/app_config.json',
    editionsUrl: 'https://www.toolstem.com/football-box-scores/feed_index.json',
    pdfUrl: (date) => `https://www.toolstem.com/football-box-scores/nfl_boxscores_${date}.pdf`,
    fileName: (date) => `football_box_scores_${date}.pdf`,
    mlb: false,
  },
};

export const ALLOWED_FETCH_HOST = 'www.toolstem.com';

/** Exact words shown next to the text checkbox in the app. The app sends
 * this version string; the server stores the matching text. */
export const SMS_CONSENT = {
  v1:
    'Text me a link to the daily paper. Up to 1 text per game day. ' +
    'Msg and data rates may apply. Reply STOP to cancel, HELP for help. ' +
    'Consent is not a condition of purchase.',
};
