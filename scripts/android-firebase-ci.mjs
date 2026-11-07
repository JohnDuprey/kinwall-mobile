// Optional GitHub Actions client configuration. Never accepts FCM server credentials.
import { writeFileSync, appendFileSync } from 'node:fs'
import { join } from 'node:path'

const source = process.env.KINWALL_GOOGLE_SERVICES_JSON
if (source) {
  let config
  try {
    config = JSON.parse(source)
    const client = config.client?.find(c => c.client_info?.android_client_info?.package_name === 'family.kinwall.app')
    if (config.type === 'service_account' || config.private_key || config.private_key_id ||
        !config.project_info?.project_id || !config.project_info?.project_number ||
        !client?.client_info?.mobilesdk_app_id || !client.api_key?.some(k => typeof k.current_key === 'string' && k.current_key)) throw Error()
  } catch {
    // JSON parser errors can include the source. Report a fixed message instead.
    console.error('Invalid Firebase Android client configuration; use google-services.json for family.kinwall.app, never a service-account key.')
    process.exit(1)
  }
  if (!process.env.RUNNER_TEMP || !process.env.GITHUB_ENV) throw Error('GitHub Actions runner paths are required')
  const file = join(process.env.RUNNER_TEMP, 'google-services.json')
  if (/[\r\n]/.test(file)) throw Error('Invalid runner path')
  writeFileSync(file, JSON.stringify(config), { mode: 0o600, flag: 'wx' })
  appendFileSync(process.env.GITHUB_ENV, `KINWALL_GOOGLE_SERVICES_FILE=${file}\n`)
}
