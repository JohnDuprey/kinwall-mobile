// Paid capabilities stay opt-in for personal-team/self-hosted builds. Both TestFlight entry points
// supply the release flags; Xcode development builds can use the sandbox with the same plugin.
exports.membership = (env) => {
  const push = env.KINWALL_PUSH === '1'
  const apnsEnvironment = env.KINWALL_APNS_ENV || 'development'
  if (push && !['development', 'production'].includes(apnsEnvironment)) throw new Error('KINWALL_APNS_ENV must be development or production')
  return { push, apnsEnvironment, appAttest: push && apnsEnvironment === 'production', timeSensitive: push || env.KINWALL_TIME_SENSITIVE === '1',
    domains: env.KINWALL_ASSOCIATED_DOMAINS === '1' ? ['applinks:kinwall.family', 'applinks:*.kinwall.family', 'webcredentials:kinwall.family', 'webcredentials:*.kinwall.family'] : [] }
}
