import { type DayPlan, type TodayScheduleStatus, todayScheduleStatus } from '@/domain/schedule';

import type { Services } from './AppContext';

/** Today's schedule status, refined by whether today's workout is in progress or already finished. */
export function resolveTodayStatus({ programs, sessions, env }: Services): TodayScheduleStatus {
  const program = programs.activeProgram();
  if (!program) return { type: 'noProgram' };
  const today = env.today();
  const status = todayScheduleStatus(today, programs.calendarSchedule(program.id), programs.workoutTitles(program.id));
  if (status.type !== 'workoutDay') return status;
  if (sessions.hasCompletedSession(status.workoutId, today)) return { ...status, type: 'workoutAlreadyFinished' };
  if (sessions.activeSession(status.workoutId, today)) return { ...status, type: 'workoutInProgress' };
  return status;
}

/** Forces today onto `plan`, realigning the days after it (see `setScheduleDayShiftingFollowing`). */
export function changeTodaysPlan({ programs, env }: Services, plan: DayPlan): void {
  programs.ensureForwardScheduleFilled();
  programs.setScheduleDayShiftingFollowing(env.today(), plan);
}
