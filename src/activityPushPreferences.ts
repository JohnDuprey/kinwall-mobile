// No native imports: choices are independently testable, and medicine starts don't depend on travel.
export type ActivityPushPreferences = { leaveBy: boolean; medications: boolean; medicationNames: boolean; kidDoses: boolean }
export function activityPushPreferences(leaveBy: boolean, medicine: unknown, allowed = true): ActivityPushPreferences {
 const m = medicine && typeof medicine === 'object' ? medicine as Record<string,unknown> : {}
 const on = allowed && m.on === true
 return {leaveBy:allowed && leaveBy,medications:on,medicationNames:on && m.names===true,kidDoses:on && m.kids===true}
}
export const activityPushWanted = (p: ActivityPushPreferences) => p.leaveBy || p.medications

/** Older self-hosted servers reject the new strict-schema field. Preserve their travel activities;
 * they cannot start medicine activities remotely until upgraded. Other failures remain failures. */
export async function registerActivityPush<T>(token: { kind: 'start'|'update'; token: string; activity?: string; endsAt?: string }, preferences: ActivityPushPreferences, register: (body: { token: string; [key: string]: unknown }) => Promise<T>, oldServer: (error: unknown) => boolean): Promise<T> {
 if (token.kind !== 'start') return register(token)
 try { return await register({...token,preferences}) }
 catch (error) { if (!oldServer(error)) throw error; return register(token) }
}
