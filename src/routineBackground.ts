import { Platform } from 'react-native'
import * as Notifications from 'expo-notifications'
import * as TaskManager from 'expo-task-manager'
import { refreshBackgroundRoutine } from './routineController'
import { runRoutineNotification } from './routineNotification'

const TASK = 'kinwall-routine-notification'
// Module-scope registration is also loaded by Expo on a headless notification launch.
// The message is only a hint; no app tokens, chore details or grant come from the payload.
if (Platform.OS === 'ios') {
  TaskManager.defineTask<Notifications.NotificationTaskPayload>(TASK, async ({ data, error }) => {
    if (error) return 2
    return runRoutineNotification(data, refreshBackgroundRoutine)
  })
  Notifications.registerTaskAsync(TASK).catch(() => {})
}
